import Foundation
import Sparkle

enum CadenceUpdateChannelPolicy {
    static func allowedChannels(
        includesBetaUpdates: Bool
    ) -> Set<String> {
        includesBetaUpdates ? ["beta"] : []
    }
}

@MainActor
protocol CadenceUpdateChecking: AnyObject {
    var automaticallyChecksForUpdates: Bool { get }

    func checkForUpdatesInBackground()
}

@MainActor
final class CadenceUpdateLaunchCoordinator {
    private var didRun = false

    func run(
        updateController: any CadenceUpdateChecking,
        notificationController: CadenceNotificationController,
        defaults: UserDefaults = .standard
    ) async {
        guard !didRun,
              updateController.automaticallyChecksForUpdates
        else {
            return
        }
        didRun = true

        if defaults.bool(
            forKey: CadenceNotificationPreferences.updateAvailabilityKey
        ) {
            _ = await notificationController.requestAuthorizationIfNeeded()
        }
        updateController.checkForUpdatesInBackground()
    }
}

@MainActor
final class CadenceUpdateController:
    NSObject,
    CadenceUpdateChecking,
    SPUUpdaterDelegate {
    static let includesBetaUpdatesKey = "updates.includesBeta"

    private let startsUpdater: Bool
    private let notificationController: CadenceNotificationController?
    private lazy var standardController = SPUStandardUpdaterController(
        startingUpdater: startsUpdater,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    init(
        startsUpdater: Bool,
        notificationController: CadenceNotificationController? = nil
    ) {
        self.startsUpdater = startsUpdater
        self.notificationController = notificationController
        super.init()
        _ = standardController
    }

    var automaticallyChecksForUpdates: Bool {
        get { standardController.updater.automaticallyChecksForUpdates }
        set {
            standardController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { standardController.updater.automaticallyDownloadsUpdates }
        set {
            standardController.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    var allowsAutomaticUpdates: Bool {
        standardController.updater.allowsAutomaticUpdates
    }

    func checkForUpdates() {
        standardController.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        standardController.updater.checkForUpdatesInBackground()
    }

    func updateChannelPreferenceDidChange() {
        standardController.updater.resetUpdateCycleAfterShortDelay()
    }

    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        CadenceUpdateChannelPolicy.allowedChannels(
            includesBetaUpdates: UserDefaults.standard.bool(
                forKey: Self.includesBetaUpdatesKey
            )
        )
    }

    func updater(
        _: SPUUpdater,
        didFindValidUpdate item: SUAppcastItem
    ) {
        notificationController?.updateDidBecomeAvailable(
            version: item.versionString,
            displayVersion: item.displayVersionString
        )
    }
}
