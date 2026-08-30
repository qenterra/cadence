import Foundation

@MainActor
protocol DisplaySleepActivityClient: AnyObject {
    func begin() -> NSObjectProtocol
    func end(_ activity: NSObjectProtocol)
}

@MainActor
final class SystemDisplaySleepActivityClient: DisplaySleepActivityClient {
    func begin() -> NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled],
            reason: String(localized: "Cadence is playing audio")
        )
    }

    func end(_ activity: NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(activity)
    }
}

@MainActor
final class DisplaySleepController {
    private let client: any DisplaySleepActivityClient
    private var activity: NSObjectProtocol?

    private(set) var isPreventingDisplaySleep = false

    init(
        client: any DisplaySleepActivityClient =
            SystemDisplaySleepActivityClient()
    ) {
        self.client = client
    }

    func update(isPlaying: Bool, isEnabled: Bool) {
        if isPlaying, isEnabled {
            guard activity == nil else {
                return
            }
            activity = client.begin()
            isPreventingDisplaySleep = true
        } else {
            stop()
        }
    }

    func stop() {
        guard let activity else {
            return
        }
        client.end(activity)
        self.activity = nil
        isPreventingDisplaySleep = false
    }

    isolated deinit {
        if let activity {
            client.end(activity)
        }
    }
}
