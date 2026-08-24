import Foundation
import Observation

enum LibrarySessionAvailability: Equatable, Sendable {
    case empty
    case recovering
    case ready
    case preview
    case failed(LibrarySessionFailure)
}

struct LibrarySessionFailure: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case locationUnavailable
        case configurationUnavailable
        case staleBookmark
        case identityMismatch
        case blockingPackageFile
        case missingMetadataStore
        case unreadableIdentity
        case openFailed
        case recoveryFailed
    }

    let kind: Kind
    let message: String
    let revealURL: URL?
}

struct LibrarySessionSwitchError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}

@MainActor
@Observable
final class LibrarySession {
    var location: ManagedLibraryLocation?
    let store: LibraryStore
    let locationController: LibraryLocationController?
    var availability: LibrarySessionAvailability
    @ObservationIgnored let transitionLease = LibrarySessionTransitionLease()

    var transitionGeneration: UInt64 {
        transitionLease.generation
    }

    private init(
        location: ManagedLibraryLocation?,
        store: LibraryStore,
        availability: LibrarySessionAvailability,
        locationController: LibraryLocationController? = nil
    ) {
        self.location = location
        self.store = store
        self.availability = availability
        self.locationController = locationController
    }

    static func startup(
        fileManager: FileManager = .default
    ) -> LibrarySession {
        do {
            let fallback = try ManagedLibraryLocation.currentUser(
                fileManager: fileManager
            )
            let controller = LibraryLocationController()
            return startup(
                resolution: controller.resolveActiveLibrary(
                    fallback: fallback
                ),
                fileManager: fileManager,
                controller: controller
            )
        } catch {
            return failed(
                location: nil,
                kind: .locationUnavailable,
                message: error.localizedDescription
            )
        }
    }

    static func startup(
        location: ManagedLibraryLocation,
        fileManager: FileManager = .default,
        locationController: LibraryLocationController? = nil
    ) -> LibrarySession {
        do {
            try location.migrateLegacyPackageIfNeeded(
                fileManager: fileManager
            )
        } catch {
            return failed(
                location: location,
                kind: .openFailed,
                message: error.localizedDescription,
                revealURL: location.musicDirectory,
                locationController: locationController
            )
        }
        let package = ManagedLibraryPackage(location: location)
        switch inspectExistingPackage(package, fileManager: fileManager) {
        case .absent:
            return LibrarySession(
                location: location,
                store: LibraryStore(),
                availability: .empty,
                locationController: locationController
            )
        case let .failed(failure):
            return failed(
                location: location,
                kind: failure.kind,
                message: failure.message,
                revealURL: failure.revealURL,
                locationController: locationController
            )
        case .valid:
            return openExistingPackage(
                package,
                at: location,
                fileManager: fileManager,
                locationController: locationController
            )
        }
    }

    private static func openExistingPackage(
        _ package: ManagedLibraryPackage,
        at location: ManagedLibraryLocation,
        fileManager: FileManager,
        locationController: LibraryLocationController?
    ) -> LibrarySession {
        do {
            let container = try LibraryContainerFactory.persistentLocal(
                package: package,
                fileManager: fileManager
            )
            return LibrarySession(
                location: location,
                store: LibraryStore(
                    container: container,
                    package: package
                ),
                availability: .recovering,
                locationController: locationController
            )
        } catch {
            return failed(
                location: location,
                kind: .openFailed,
                message: error.localizedDescription,
                locationController: locationController
            )
        }
    }

    func prepareForLibraryReplacement() async throws {
        try await performTransition { transition in
            try await self.prepareForLibraryReplacementLocked(
                transition: transition
            )
        }
    }

    func activate(
        repository: LibraryRepository,
        package: ManagedLibraryPackage? = nil,
        snapshotLoader: InitialLibrarySnapshotLoader? = nil
    ) async throws {
        try await performTransition { transition in
            try await self.activateLocked(
                repository: repository,
                package: package,
                transition: transition,
                snapshotLoader: snapshotLoader
            )
        }
    }

    func finishActivationLocked(
        transition: LibrarySessionTransitionToken,
        snapshotLoader: InitialLibrarySnapshotLoader? = nil
    ) async throws {
        let context = store.captureLibraryContext()
        await store.loadInitialLibrary(snapshotLoader: snapshotLoader)
        try requireCurrentTransition(transition, context: context)
        switch store.availability {
        case .ready:
            availability = .ready
        case let .failed(failure):
            publishFailure(kind: .openFailed, message: failure.message)
        case .empty:
            availability = .empty
        case .loading:
            publishFailure(
                kind: .openFailed,
                message: "The managed library did not finish loading."
            )
        }
    }

    func requireTransitionOwnership(
        _ transition: LibrarySessionTransitionToken
    ) throws {
        try requireCurrentTransition(transition)
    }

    func switchLocation(
        to location: ManagedLibraryLocation,
        repository: LibraryRepository,
        lyricsSearchIndexer: (any LyricsSearchIndexing)? = nil,
        snapshotLoader: InitialLibrarySnapshotLoader? = nil
    ) async throws {
        try await performTransition { transition in
            let previousLocation = self.location
            let previousRepository = self.store.repository
            do {
                try await self.store.attach(
                    repository: repository,
                    package: ManagedLibraryPackage(location: location),
                    lyricsSearchIndexer: lyricsSearchIndexer
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard self.ownsTransition(transition) else {
                    throw CancellationError()
                }
                self.publishFailure(
                    kind: .openFailed,
                    message: error.localizedDescription
                )
                throw error
            }
            try self.requireCurrentTransition(transition)
            self.location = location
            let context = self.store.captureLibraryContext()
            await self.store.loadInitialLibrary(snapshotLoader: snapshotLoader)
            try self.requireCurrentTransition(
                transition,
                context: context
            )
            if case let .failed(failure) = self.store.availability {
                try await self.restoreAfterFailedSwitch(
                    failure: failure,
                    previousLocation: previousLocation,
                    previousRepository: previousRepository,
                    transition: transition
                )
            }
            try self.publishReplacementAvailability()
        }
    }
}

extension LibrarySession {
    static func preview() -> LibrarySession {
        LibrarySession(
            location: nil,
            store: LibraryStore(),
            availability: .preview
        )
    }

    func fail(
        kind: LibrarySessionFailure.Kind = .recoveryFailed,
        message: String
    ) {
        transitionLease.invalidate()
        publishFailure(kind: kind, message: message)
    }

    static func failed(
        location: ManagedLibraryLocation?,
        kind: LibrarySessionFailure.Kind,
        message: String,
        revealURL: URL? = nil,
        locationController: LibraryLocationController? = nil
    ) -> LibrarySession {
        LibrarySession(
            location: location,
            store: LibraryStore(),
            availability: .failed(
                LibrarySessionFailure(
                    kind: kind,
                    message: message,
                    revealURL: revealURL ?? location?.packageURL
                )
            ),
            locationController: locationController
        )
    }
}
