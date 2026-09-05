@testable import Cadence
import Foundation
import Testing

@MainActor
struct DisplaySleepControllerTests {
    @Test("Display sleep activity exists only while enabled playback is active")
    func playbackOwnership() {
        let client = DisplaySleepActivityClientSpy()
        let controller = DisplaySleepController(client: client)

        controller.update(isPlaying: false, isEnabled: true)
        #expect(client.beginCount == 0)

        controller.update(isPlaying: true, isEnabled: true)
        controller.update(isPlaying: true, isEnabled: true)
        #expect(client.beginCount == 1)
        #expect(controller.isPreventingDisplaySleep)

        controller.update(isPlaying: true, isEnabled: false)
        #expect(client.endCount == 1)
        #expect(!controller.isPreventingDisplaySleep)

        controller.update(isPlaying: true, isEnabled: true)
        controller.update(isPlaying: false, isEnabled: true)
        #expect(client.beginCount == 2)
        #expect(client.endCount == 2)
    }
}

@MainActor
private final class DisplaySleepActivityClientSpy:
    DisplaySleepActivityClient {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    func begin() -> NSObjectProtocol {
        beginCount += 1
        return NSObject()
    }

    func end(_: NSObjectProtocol) {
        endCount += 1
    }
}
