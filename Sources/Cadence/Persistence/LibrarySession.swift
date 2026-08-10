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
        case staleBookmark
        case identityMismatch
        case blockingPackageFile
        case missingMetadataStore
        case openFailed
        case recoveryFailed
    }

    let kind: Kind
    let message: String
    let revealURL: URL?
}

private struct LibrarySessionSwitchError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}

@MainActor
@Observable
final class LibrarySession {
    private(set) var location: ManagedLibraryLocation?
    let store: LibraryStore
    let locationController: LibraryLocationController?
    private(set) var availability: LibrarySessionAvailability

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
            switch controller.resolveActiveLibrary(fallback: fallback) {
            case let .available(location):
                return startup(
                    location: location,
                    fileManager: fileManager,
                    locationController: controller
                )
            case let .unavailable(previousParent):
                return failed(
                    location: previousParent.map(
                        ManagedLibraryLocation.init(musicDirectory:)
                    ),
                    kind: .locationUnavailable,
                    message: "The saved library location is unavailable.",
                    locationController: controller
                )
            case let .staleBookmark(previousParent):
                return failed(
                    location: ManagedLibraryLocation(
                        musicDirectory: previousParent
                    ),
                    kind: .staleBookmark,
                    message: "The saved library permission must be renewed.",
                    locationController: controller
                )
            case let .identityMismatch(expected, actual):
                return failed(
                    location: nil,
                    kind: .identityMismatch,
                    message: "Expected library \(expected.id), found \(actual.id).",
                    locationController: controller
                )
            }
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
        let package = ManagedLibraryPackage(location: location)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: package.packageURL.path,
            isDirectory: &isDirectory
        ) else {
            return LibrarySession(
                location: location,
                store: LibraryStore(),
                availability: .empty,
                locationController: locationController
            )
        }

        guard isDirectory.boolValue else {
            return failed(
                location: location,
                kind: .blockingPackageFile,
                message: "A file blocks \(ManagedLibraryLocation.packageFilename).",
                locationController: locationController
            )
        }

        guard fileManager.fileExists(
            atPath: package.metadataStoreURL.path
        ) else {
            return failed(
                location: location,
                kind: .missingMetadataStore,
                message: "Cadence.library is missing its metadata store.",
                locationController: locationController
            )
        }

        do {
            let container = try LibraryContainerFactory.persistent(
                package: package
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

    func prepareForLibraryReplacement() {
        availability = .recovering
        store.detach()
    }

    func activate(
        repository: LibraryRepository
    ) async {
        availability = .recovering
        store.attach(
            repository: repository,
            package: location.map(ManagedLibraryPackage.init)
        )
        await store.loadInitialLibrary()
        if case let .failed(failure) = store.availability {
            availability = .failed(
                LibrarySessionFailure(
                    kind: .openFailed,
                    message: failure.message,
                    revealURL: location?.packageURL
                )
            )
        } else {
            availability = .ready
        }
    }

    func switchLocation(
        to location: ManagedLibraryLocation,
        repository: LibraryRepository
    ) async throws {
        let previousLocation = self.location
        let previousRepository = store.repository
        availability = .recovering
        self.location = location
        store.attach(
            repository: repository,
            package: ManagedLibraryPackage(location: location)
        )
        await store.loadInitialLibrary()
        if case let .failed(failure) = store.availability {
            self.location = previousLocation
            if let previousRepository {
                store.attach(
                    repository: previousRepository,
                    package: previousLocation.map(ManagedLibraryPackage.init)
                )
                await store.loadInitialLibrary()
            }
            availability = previousRepository == nil ? .empty : .ready
            throw LibrarySessionSwitchError(message: failure.message)
        } else {
            availability = .ready
        }
    }

    func finishRecoveryWithoutLibrary() {
        availability = .empty
    }

    func fail(
        kind: LibrarySessionFailure.Kind = .recoveryFailed,
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

    private static func failed(
        location: ManagedLibraryLocation?,
        kind: LibrarySessionFailure.Kind,
        message: String,
        locationController: LibraryLocationController? = nil
    ) -> LibrarySession {
        LibrarySession(
            location: location,
            store: LibraryStore(),
            availability: .failed(
                LibrarySessionFailure(
                    kind: kind,
                    message: message,
                    revealURL: location?.packageURL
                )
            ),
            locationController: locationController
        )
    }
}
