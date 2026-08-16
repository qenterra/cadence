@testable import Cadence
import Foundation
import Testing

@MainActor
struct CadenceInstanceCoordinatorTests {
    @Test("The first process owns the library and receives local open batches")
    func ownerReceivesLocalOpenBatch() {
        let lock = InstanceLockStub(claimsOwnership: true)
        let messaging = InstanceMessagingStub()
        let activator = InstanceActivatorStub()
        let coordinator = CadenceInstanceCoordinator(
            lock: lock,
            messaging: messaging,
            activator: activator
        )
        var received: [[URL]] = []

        #expect(coordinator.claim() == .owner)
        coordinator.connect { received.append($0) }
        coordinator.route(urls: [URL(filePath: "/tmp/One.flac")])

        #expect(received == [[URL(filePath: "/tmp/One.flac")]])
        #expect(messaging.sentBatches.isEmpty)
    }

    @Test("A duplicate forwards only file URLs and activates the owner")
    func duplicateForwardsFiles() throws {
        let lock = InstanceLockStub(claimsOwnership: false)
        let messaging = InstanceMessagingStub()
        let activator = InstanceActivatorStub()
        let coordinator = CadenceInstanceCoordinator(
            lock: lock,
            messaging: messaging,
            activator: activator
        )
        let file = URL(filePath: "/tmp/Two.mp3")
        let remote = try #require(URL(string: "https://example.com/track.mp3"))

        #expect(coordinator.claim() == .duplicate)
        coordinator.route(urls: [remote, file])
        coordinator.activateOwner()

        #expect(messaging.sentBatches == [[file]])
        #expect(activator.activationCount == 1)
        #expect(!CadenceMainScenePolicy.allowsMultipleWindows)
    }

    @Test("Remote batches are delivered to the owning process")
    func ownerReceivesRemoteBatch() {
        let messaging = InstanceMessagingStub()
        let coordinator = CadenceInstanceCoordinator(
            lock: InstanceLockStub(claimsOwnership: true),
            messaging: messaging,
            activator: InstanceActivatorStub()
        )
        let file = URL(filePath: "/tmp/Remote.aiff")
        var received: [[URL]] = []

        _ = coordinator.claim()
        coordinator.connect { received.append($0) }
        messaging.emit([file])

        #expect(received == [[file]])
    }
}

@MainActor
private final class InstanceLockStub: CadenceInstanceLocking {
    let claimsOwnership: Bool

    init(claimsOwnership: Bool) {
        self.claimsOwnership = claimsOwnership
    }

    func claim() -> Bool {
        claimsOwnership
    }
}

@MainActor
private final class InstanceMessagingStub: CadenceInstanceMessaging {
    private var handler: (([URL]) -> Void)?
    private(set) var sentBatches: [[URL]] = []

    func startReceiving(
        _ handler: @escaping ([URL]) -> Void
    ) {
        self.handler = handler
    }

    func send(urls: [URL]) {
        sentBatches.append(urls)
    }

    func emit(_ urls: [URL]) {
        handler?(urls)
    }
}

@MainActor
private final class InstanceActivatorStub: CadenceInstanceActivating {
    private(set) var activationCount = 0

    func activateOwner() {
        activationCount += 1
    }
}
