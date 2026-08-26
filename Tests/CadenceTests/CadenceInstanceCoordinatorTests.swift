@testable import Cadence
import Foundation
import Testing

@MainActor
struct CadenceInstanceCoordinatorTests {
    @Test("Instance messaging does not access authentication at initialization")
    func instanceMessagingLoadsAuthenticationLazily() {
        var creationCount = 0

        _ = DistributedCadenceInstanceMessaging(
            authenticatorFactory: {
                creationCount += 1
                return CadenceInstanceMessageAuthenticator(
                    secret: Data(repeating: 3, count: 32)
                )
            }
        )

        #expect(creationCount == 0)
    }

    @Test("Instance messages reject a modified signed payload")
    func instanceMessagesRejectModifiedPayload() {
        let authenticator = CadenceInstanceMessageAuthenticator(
            secret: Data(repeating: 7, count: 32)
        )
        let paths = ["/tmp/One.flac", "/tmp/Two.mp3"]
        let signature = authenticator.signature(for: paths)

        #expect(authenticator.verifies(signature: signature, paths: paths))
        #expect(
            !authenticator.verifies(
                signature: signature,
                paths: ["/tmp/One.flac", "/tmp/Injected.mp3"]
            )
        )
    }

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
