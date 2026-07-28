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
    let message: String
}

@MainActor
@Observable
final class LibrarySession {
    let location: ManagedLibraryLocation?
    let store: LibraryStore
    private(set) var availability: LibrarySessionAvailability

    private init(
        location: ManagedLibraryLocation?,
        store: LibraryStore,
        availability: LibrarySessionAvailability
    ) {
        self.location = location
        self.store = store
        self.availability = availability
    }

    static func startup(
        fileManager: FileManager = .default
    ) -> LibrarySession {
        do {
            return try startup(
                location: .currentUser(fileManager: fileManager),
                fileManager: fileManager
            )
        } catch {
            return failed(
                location: nil,
                message: error.localizedDescription
            )
        }
    }

    static func startup(
        location: ManagedLibraryLocation,
        fileManager: FileManager = .default
    ) -> LibrarySession {
        let package = ManagedLibraryPackage(location: location)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: package.packageURL.path,
            isDirectory: &isDirectory
        ) else {
            return LibrarySession(
                location: location,
                store: LibraryStore(),
                availability: .empty
            )
        }

        guard isDirectory.boolValue else {
            return failed(
                location: location,
                message: "A file blocks \(ManagedLibraryLocation.packageFilename)."
            )
        }

        guard fileManager.fileExists(
            atPath: package.metadataStoreURL.path
        ) else {
            return failed(
                location: location,
                message: "Cadence.library is missing its metadata store."
            )
        }

        do {
            let container = try LibraryContainerFactory.persistent(
                package: package
            )
            return LibrarySession(
                location: location,
                store: LibraryStore(container: container),
                availability: .ready
            )
        } catch {
            return failed(
                location: location,
                message: error.localizedDescription
            )
        }
    }

    static func preview() -> LibrarySession {
        LibrarySession(
            location: nil,
            store: LibraryStore(),
            availability: .preview
        )
    }

    func beginRecovery() {
        availability = .recovering
    }

    func activate(
        repository: LibraryRepository
    ) async {
        availability = .recovering
        store.attach(repository: repository)
        await store.loadInitialLibrary()
        if case let .failed(failure) = store.availability {
            availability = .failed(
                LibrarySessionFailure(message: failure.message)
            )
        } else {
            availability = .ready
        }
    }

    func finishRecoveryWithoutLibrary() {
        availability = .empty
    }

    func fail(
        message: String
    ) {
        availability = .failed(
            LibrarySessionFailure(message: message)
        )
    }

    private static func failed(
        location: ManagedLibraryLocation?,
        message: String
    ) -> LibrarySession {
        LibrarySession(
            location: location,
            store: LibraryStore(),
            availability: .failed(
                LibrarySessionFailure(message: message)
            )
        )
    }
}
