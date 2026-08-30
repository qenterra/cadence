import Foundation
import UserNotifications

enum CadenceNotificationPreferences {
    static let trackChangesKey = "notifications.trackChanges"
    static let updateAvailabilityKey = "notifications.updateAvailability"
    static let lastUpdateVersionKey = "notifications.lastUpdateVersion"
}

enum CadenceNotificationAuthorization: Equatable, Sendable {
    case authorized
    case denied
    case notDetermined
}

struct CadenceNotificationMessage: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
}

@MainActor
protocol CadenceSystemNotificationCenter: AnyObject {
    func authorizationStatus() async -> CadenceNotificationAuthorization
    func requestAuthorization() async throws -> Bool
    func deliver(_ notification: CadenceNotificationMessage)
}

@MainActor
final class CadenceNotificationController {
    private let center: any CadenceSystemNotificationCenter
    private let defaults: UserDefaults
    private var lastObservedPlayingTrackID: UUID?
    private var authorizationTask: Task<Bool, Never>?

    init(
        center: any CadenceSystemNotificationCenter =
            MacOSCadenceNotificationCenter(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        if let authorizationTask {
            return await authorizationTask.value
        }

        switch await center.authorizationStatus() {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            if let authorizationTask {
                return await authorizationTask.value
            }
            let task = Task { [center] in
                await (try? center.requestAuthorization()) == true
            }
            authorizationTask = task
            let isAuthorized = await task.value
            authorizationTask = nil
            return isAuthorized
        }
    }

    func playbackStateDidChange(_ state: PlaybackCoordinatorState) {
        guard state.transport == .playing,
              let track = state.currentTrack
        else {
            return
        }

        let didChangeTrack = track.id != lastObservedPlayingTrackID
        lastObservedPlayingTrackID = track.id
        guard didChangeTrack,
              defaults.bool(
                  forKey: CadenceNotificationPreferences.trackChangesKey
              )
        else {
            return
        }

        center.deliver(
            CadenceNotificationMessage(
                identifier: "cadence.track-change",
                title: track.title,
                body: trackNotificationBody(for: track)
            )
        )
    }

    func updateDidBecomeAvailable(
        version: String,
        displayVersion: String
    ) {
        guard defaults.bool(
            forKey: CadenceNotificationPreferences.updateAvailabilityKey
        ), defaults.string(
            forKey: CadenceNotificationPreferences.lastUpdateVersionKey
        ) != version else {
            return
        }

        defaults.set(
            version,
            forKey: CadenceNotificationPreferences.lastUpdateVersionKey
        )
        center.deliver(
            CadenceNotificationMessage(
                identifier: "cadence.update.\(version)",
                title: String(localized: "Cadence Update Available"),
                body: String(
                    localized: "Version \(displayVersion) is ready to install."
                )
            )
        )
    }

    private func trackNotificationBody(for track: PlaybackTrack) -> String {
        let metadata = [track.artist, track.album].filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return metadata.isEmpty
            ? String(localized: "Now Playing")
            : metadata.joined(separator: " — ")
    }
}

@MainActor
final class MacOSCadenceNotificationCenter:
    NSObject,
    CadenceSystemNotificationCenter,
    UNUserNotificationCenterDelegate {
    nonisolated static let foregroundPresentationOptions:
        UNNotificationPresentationOptions = [.banner]

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func authorizationStatus() async -> CadenceNotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }

    func deliver(_ notification: CadenceNotificationMessage) {
        let content = Self.content(for: notification)
        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: nil
        )
        Task {
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler:
        @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.foregroundPresentationOptions)
    }

    static func content(
        for notification: CadenceNotificationMessage
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.interruptionLevel = .active
        return content
    }
}
