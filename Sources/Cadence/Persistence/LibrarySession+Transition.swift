import Foundation

extension LibrarySession {
    func prepareForLibraryReplacementLocked(
        transition: LibrarySessionTransitionToken
    ) async throws {
        do {
            try requireCurrentTransition(transition)
            try await store.detach()
            try requireCurrentTransition(transition)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard
                ownsTransition(transition),
                transitionLease.isOwner(transition)
            else {
                throw CancellationError()
            }
            publishFailure(
                kind: .openFailed,
                message: error.localizedDescription
            )
            throw error
        }
    }

    func activateLocked(
        repository: LibraryRepository,
        package: ManagedLibraryPackage? = nil,
        transition: LibrarySessionTransitionToken,
        snapshotLoader: InitialLibrarySnapshotLoader? = nil
    ) async throws {
        do {
            try requireCurrentTransition(transition)
            try await store.attach(
                repository: repository,
                package: package
                    ?? location.map(ManagedLibraryPackage.init)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard
                ownsTransition(transition),
                transitionLease.isOwner(transition)
            else {
                throw CancellationError()
            }
            publishFailure(
                kind: .openFailed,
                message: error.localizedDescription
            )
            throw error
        }
        try requireCurrentTransition(transition)
        try await finishActivationLocked(
            transition: transition,
            snapshotLoader: snapshotLoader
        )
    }

    func performTransition<Result>(
        _ operation: @MainActor (
            LibrarySessionTransitionToken
        ) async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        let transition = transitionLease.reserve()
        availability = .recovering
        return try await transitionLease.withLease(for: transition) {
            try self.requireCurrentTransition(transition)
            do {
                let result = try await operation(transition)
                try self.requireCurrentTransition(transition)
                return result
            } catch {
                guard self.ownsTransition(transition) else {
                    throw CancellationError()
                }
                throw error
            }
        }
    }

    func ownsTransition(
        _ transition: LibrarySessionTransitionToken
    ) -> Bool {
        transitionLease.isCurrent(transition)
    }

    func requireCurrentTransition(
        _ transition: LibrarySessionTransitionToken,
        context: LibraryStoreContext? = nil
    ) throws {
        try Task.checkCancellation()
        let ownsContext = if let context {
            store.isCurrentLibraryContext(context)
        } else {
            true
        }
        guard
            ownsTransition(transition),
            transitionLease.isOwner(transition),
            ownsContext
        else {
            throw CancellationError()
        }
    }

    func requireTransitionLeaseOwnership(
        _ transition: LibrarySessionTransitionToken,
        context: LibraryStoreContext? = nil
    ) throws {
        let ownsContext = if let context {
            store.isCurrentLibraryContext(context)
        } else {
            true
        }
        guard transitionLease.isOwner(transition), ownsContext else {
            throw CancellationError()
        }
    }

    func detachForResetCompensationLocked(
        transition: LibrarySessionTransitionToken
    ) async throws {
        try requireTransitionLeaseOwnership(transition)
        try await store.detach()
        try requireTransitionLeaseOwnership(transition)
    }

    func restoreLibraryForResetCompensationLocked(
        repository: LibraryRepository,
        package: ManagedLibraryPackage,
        transition: LibrarySessionTransitionToken
    ) async throws -> Bool {
        try requireTransitionLeaseOwnership(transition)
        try await store.attach(
            repository: repository,
            package: package
        )
        try requireTransitionLeaseOwnership(transition)
        let context = store.captureLibraryContext()
        await store.loadInitialLibrary()
        try requireTransitionLeaseOwnership(
            transition,
            context: context
        )
        guard !transitionLease.hasCurrentWaiter else {
            return false
        }
        switch store.availability {
        case .ready:
            availability = .ready
        case .empty:
            availability = .empty
        case let .failed(failure):
            throw LibrarySessionSwitchError(message: failure.message)
        case .loading:
            throw LibrarySessionSwitchError(
                message: "The restored managed library did not finish loading."
            )
        }
        return true
    }

    @discardableResult
    func publishResetCompensationFailureLocked(
        message: String,
        transition: LibrarySessionTransitionToken
    ) throws -> Bool {
        try requireTransitionLeaseOwnership(transition)
        guard !transitionLease.hasCurrentWaiter else {
            return false
        }
        publishFailure(kind: .recoveryFailed, message: message)
        return true
    }

    func publishFailure(
        kind: LibrarySessionFailure.Kind,
        message: String
    ) {
        availability = .failed(
            LibrarySessionFailure(
                kind: kind,
                message: message,
                revealURL: location?.packageURL
            )
        )
    }

    func publishFailure(
        kind: LibrarySessionFailure.Kind,
        message: String,
        transition: LibrarySessionTransitionToken
    ) throws {
        try requireCurrentTransition(transition)
        publishFailure(kind: kind, message: message)
    }

    func restoreAfterFailedSwitch(
        failure: LibraryStoreFailure,
        previousLocation: ManagedLibraryLocation?,
        previousRepository: LibraryRepository?,
        transition: LibrarySessionTransitionToken
    ) async throws {
        let switchError = LibrarySessionSwitchError(message: failure.message)
        do {
            try await restorePreviousLibrary(
                location: previousLocation,
                repository: previousRepository,
                transition: transition
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard ownsTransition(transition) else {
                throw CancellationError()
            }
            let rollbackError = LibrarySessionSwitchError(
                message: switchError.message
                    + " The previous managed library could not be restored: "
                    + error.localizedDescription
            )
            publishFailure(kind: .openFailed, message: rollbackError.message)
            throw rollbackError
        }
        throw switchError
    }

    func publishReplacementAvailability() throws {
        guard store.availability == .ready else {
            let error = LibrarySessionSwitchError(
                message: "The replacement managed library did not become ready."
            )
            publishFailure(kind: .openFailed, message: error.message)
            throw error
        }
        availability = .ready
    }

    func restorePreviousLibrary(
        location: ManagedLibraryLocation?,
        repository: LibraryRepository?,
        transition: LibrarySessionTransitionToken
    ) async throws {
        guard let repository else {
            try await store.detach()
            try requireCurrentTransition(transition)
            self.location = location
            availability = .empty
            return
        }

        try await store.attach(
            repository: repository,
            package: location.map(ManagedLibraryPackage.init)
        )
        try requireCurrentTransition(transition)
        self.location = location
        let context = store.captureLibraryContext()
        await store.loadInitialLibrary()
        try requireCurrentTransition(transition, context: context)
        guard store.availability == .ready else {
            let message = if case let .failed(failure) = store.availability {
                failure.message
            } else {
                "The previous managed library did not become ready."
            }
            throw LibrarySessionSwitchError(message: message)
        }
        availability = .ready
    }
}
