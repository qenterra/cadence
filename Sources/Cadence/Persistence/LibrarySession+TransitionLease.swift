import Foundation

struct LibrarySessionTransitionToken: Equatable, Sendable {
    fileprivate let generation: UInt64
}

@MainActor
final class LibrarySessionTransitionLease {
    private struct Waiter {
        let id: UUID
        let transition: LibrarySessionTransitionToken
        let continuation: CheckedContinuation<Void, any Error>
    }

    private(set) var generation: UInt64 = 0
    private var owner: LibrarySessionTransitionToken?
    private var waiters: [Waiter] = []

    var isIdle: Bool {
        owner == nil && waiters.isEmpty
    }

    var ownerGeneration: UInt64? {
        owner?.generation
    }

    var hasCurrentWaiter: Bool {
        waiters.contains { isCurrent($0.transition) }
    }

    func reserve() -> LibrarySessionTransitionToken {
        generation &+= 1
        return LibrarySessionTransitionToken(generation: generation)
    }

    func invalidate() {
        generation &+= 1
    }

    func isCurrent(_ transition: LibrarySessionTransitionToken) -> Bool {
        transition.generation == generation
    }

    func isOwner(_ transition: LibrarySessionTransitionToken) -> Bool {
        owner == transition
    }

    func withLease<Result>(
        for transition: LibrarySessionTransitionToken,
        operation: @MainActor () async throws -> Result
    ) async throws -> Result {
        try await acquire(for: transition)
        defer { release(transition) }

        do {
            try Task.checkCancellation()
            try requireOwnership(of: transition)
            let result = try await operation()
            try Task.checkCancellation()
            try requireOwnership(of: transition)
            return result
        } catch {
            guard isCurrent(transition) else {
                throw CancellationError()
            }
            throw error
        }
    }

    private func acquire(
        for transition: LibrarySessionTransitionToken
    ) async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled, isCurrent(transition) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard owner != nil else {
                    owner = transition
                    continuation.resume()
                    return
                }
                waiters.append(
                    Waiter(
                        id: waiterID,
                        transition: transition,
                        continuation: continuation
                    )
                )
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(id: waiterID)
            }
        })
    }

    private func requireOwnership(
        of transition: LibrarySessionTransitionToken
    ) throws {
        guard isCurrent(transition), isOwner(transition) else {
            throw CancellationError()
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release(_ transition: LibrarySessionTransitionToken) {
        guard owner == transition else {
            return
        }
        owner = nil
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            guard isCurrent(waiter.transition) else {
                waiter.continuation.resume(throwing: CancellationError())
                continue
            }
            owner = waiter.transition
            waiter.continuation.resume()
            return
        }
    }
}
