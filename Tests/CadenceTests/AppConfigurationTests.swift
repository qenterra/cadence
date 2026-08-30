@testable import Cadence
import Foundation
import Testing
import UserNotifications

struct AppConfigurationTests {
    @Test("Unit-test hosts never open the current user's library")
    func hostUsesPreviewLibrary() {
        let testEnvironment = [
            "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration",
        ]

        #expect(
            CadenceLaunchEnvironment.shouldUsePreviewLibrary(
                environment: testEnvironment
            )
        )
        #expect(
            !CadenceLaunchEnvironment.shouldEnforceSingleInstance(
                environment: testEnvironment
            )
        )
        #expect(
            !CadenceLaunchEnvironment.shouldUsePreviewLibrary(
                environment: [:]
            )
        )
        #expect(
            CadenceLaunchEnvironment.shouldEnforceSingleInstance(
                environment: [:]
            )
        )
    }

    @Test("Cadence targets the configured macOS baseline")
    func deploymentTarget() {
        #expect(AppConfiguration.minimumDeploymentTarget == "26.0")
        #expect(AppConfiguration.bundleIdentifier == "com.qenterra.cadence")
    }

    @Test("Public project links point to QenTerra-owned destinations")
    func publicLinks() {
        #expect(
            AppConfiguration.creatorName
                == "Nikita Melnychenko (QenTerra)"
        )
        #expect(
            AppConfiguration.projectURL.absoluteString
                == "https://github.com/QenTerra/cadence"
        )
        #expect(
            AppConfiguration.licenseURL.absoluteString
                == "https://github.com/QenTerra/cadence/blob/main/LICENSE"
        )
        #expect(
            AppConfiguration.wikiURL.absoluteString
                == "https://github.com/QenTerra/cadence/wiki"
        )
        #expect(
            AppConfiguration.thirdPartyNoticesURL.absoluteString
                == "https://github.com/QenTerra/cadence/blob/main/THIRD_PARTY_NOTICES.md"
        )
        #expect(
            AppConfiguration.updateFeedURL.absoluteString
                == "https://raw.githubusercontent.com/QenTerra/cadence/main/appcast.xml"
        )
    }

    @Test("Stable updates exclude prereleases unless beta updates are enabled")
    func updateChannelPolicy() {
        #expect(
            CadenceUpdateChannelPolicy.allowedChannels(
                includesBetaUpdates: false
            ).isEmpty
        )
        #expect(
            CadenceUpdateChannelPolicy.allowedChannels(
                includesBetaUpdates: true
            ) == Set(["beta"])
        )
    }
}

@MainActor
struct CadenceNotificationControllerTests {
    @Test("System notification owner installs the foreground delegate")
    func foregroundDelegateOwnership() {
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        defer { center.delegate = previousDelegate }

        let notifications = MacOSCadenceNotificationCenter(center: center)

        #expect((center.delegate as AnyObject?) === notifications)
    }

    @Test("Foreground notifications request a temporary banner without sound")
    func foregroundBannerPresentation() {
        let options =
            MacOSCadenceNotificationCenter.foregroundPresentationOptions
        let content = MacOSCadenceNotificationCenter.content(
            for: CadenceNotificationMessage(
                identifier: "test.notification",
                title: "Track",
                body: "Artist"
            )
        )

        #expect(options == [.banner])
        #expect(content.interruptionLevel == .active)
        #expect(content.sound == nil)
    }

    @Test("Notification permission is requested only from an undecided state")
    func permissionRequestPolicy() async throws {
        let (defaults, suiteName) = try notificationTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = CadenceNotificationCenterSpy()
        let controller = CadenceNotificationController(
            center: center,
            defaults: defaults
        )

        #expect(await controller.requestAuthorizationIfNeeded())
        #expect(center.authorizationRequestCount == 1)

        center.authorization = .authorized
        #expect(await controller.requestAuthorizationIfNeeded())
        #expect(center.authorizationRequestCount == 1)

        center.authorization = .denied
        #expect(await !(controller.requestAuthorizationIfNeeded()))
        #expect(center.authorizationRequestCount == 1)
    }

    @Test("Track alerts wait for a real track change in playing state")
    func trackChangePolicy() throws {
        let (defaults, suiteName) = try notificationTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = CadenceNotificationCenterSpy()
        let controller = CadenceNotificationController(
            center: center,
            defaults: defaults
        )
        let first = playbackTestTrack(id: UUID(), title: "First").track
        let second = playbackTestTrack(id: UUID(), title: "Second").track

        controller.playbackStateDidChange(state(.playing, track: first))
        defaults.set(
            true,
            forKey: CadenceNotificationPreferences.trackChangesKey
        )
        controller.playbackStateDidChange(state(.playing, track: first))
        controller.playbackStateDidChange(state(.loading, track: second))
        controller.playbackStateDidChange(state(.playing, track: second))
        controller.playbackStateDidChange(state(.paused, track: second))
        controller.playbackStateDidChange(state(.playing, track: second))

        #expect(center.notifications.count == 1)
        #expect(center.notifications.first?.title == "Second")
        #expect(center.notifications.first?.body == "Artist — Album")
    }

    @Test("Update alerts are persisted and deduplicated by build version")
    func updateVersionPolicy() throws {
        let (defaults, suiteName) = try notificationTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            true,
            forKey: CadenceNotificationPreferences.updateAvailabilityKey
        )
        let center = CadenceNotificationCenterSpy()
        var controller = CadenceNotificationController(
            center: center,
            defaults: defaults
        )

        controller.updateDidBecomeAvailable(
            version: "3",
            displayVersion: "0.3.0"
        )
        controller.updateDidBecomeAvailable(
            version: "3",
            displayVersion: "0.3.0"
        )
        controller = CadenceNotificationController(
            center: center,
            defaults: defaults
        )
        controller.updateDidBecomeAvailable(
            version: "3",
            displayVersion: "0.3.0"
        )
        controller.updateDidBecomeAvailable(
            version: "4",
            displayVersion: "0.4.0"
        )

        #expect(center.notifications.count == 2)
        #expect(center.notifications.last?.title == "Cadence Update Available")
        #expect(center.notifications.last?.body == "Version 0.4.0 is ready to install.")
        #expect(
            defaults.string(
                forKey: CadenceNotificationPreferences.lastUpdateVersionKey
            ) == "4"
        )
    }

    private func notificationTestDefaults() throws -> (UserDefaults, String) {
        let suite = "CadenceNotificationTests-\(UUID().uuidString)"
        return try (#require(UserDefaults(suiteName: suite)), suite)
    }

    private func state(
        _ transport: PlaybackTransportState,
        track: PlaybackTrack
    ) -> PlaybackCoordinatorState {
        PlaybackCoordinatorState(
            transport: transport,
            currentTrack: track
        )
    }
}

@MainActor
final class CadenceNotificationCenterSpy: CadenceSystemNotificationCenter {
    var authorization = CadenceNotificationAuthorization.notDetermined
    var authorizationResult = true
    private(set) var authorizationRequestCount = 0
    private(set) var notifications: [CadenceNotificationMessage] = []

    func authorizationStatus() async -> CadenceNotificationAuthorization {
        authorization
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return authorizationResult
    }

    func deliver(_ notification: CadenceNotificationMessage) {
        notifications.append(notification)
    }
}
