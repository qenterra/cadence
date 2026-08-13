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

private struct LibrarySessionSwitchError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}

private enum ExistingLibraryPackageInspection {
    case absent
    case valid
    case failed(LibrarySessionFailure)
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
            break
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

private extension LibrarySession {
    static func inspectExistingPackage(
        _ package: ManagedLibraryPackage,
        fileManager: FileManager
    ) -> ExistingLibraryPackageInspection {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: package.packageURL.path,
            isDirectory: &isDirectory
        ) else {
            return .absent
        }
        guard isDirectory.boolValue else {
            return .failed(
                LibrarySessionFailure(
                    kind: .blockingPackageFile,
                    message: "A file blocks \(ManagedLibraryLocation.packageFilename).",
                    revealURL: package.packageURL
                )
            )
        }
        guard fileManager.fileExists(atPath: package.metadataStoreURL.path) else {
            return .failed(
                LibrarySessionFailure(
                    kind: .missingMetadataStore,
                    message: "Cadence.library is missing its metadata store.",
                    revealURL: package.packageURL
                )
            )
        }
        do {
            _ = try package.readIdentity()
            return .valid
        } catch {
            return .failed(
                LibrarySessionFailure(
                    kind: .unreadableIdentity,
                    message: "Cadence.library has an unreadable library identity.",
                    revealURL: package.identityURL
                )
            )
        }
    }

    static func startup(
        resolution: LibraryLocationResolution,
        fileManager: FileManager,
        controller: LibraryLocationController
    ) -> LibrarySession {
        switch resolution {
        case let .available(location):
            startup(
                location: location,
                fileManager: fileManager,
                locationController: controller
            )
        case let .unavailable(previousParent):
            failed(
                location: previousParent.map(
                    ManagedLibraryLocation.init(musicDirectory:)
                ),
                kind: .locationUnavailable,
                message: "The saved library location is unavailable.",
                locationController: controller
            )
        case let .configurationUnavailable(message):
            failed(
                location: nil,
                kind: .configurationUnavailable,
                message: message,
                locationController: controller
            )
        case let .staleBookmark(previousParent):
            failed(
                location: ManagedLibraryLocation(
                    musicDirectory: previousParent
                ),
                kind: .staleBookmark,
                message: "The saved library permission must be renewed.",
                locationController: controller
            )
        case let .identityMismatch(expected, actual):
            failed(
                location: nil,
                kind: .identityMismatch,
                message: "Expected library \(expected.id), found \(actual.id).",
                locationController: controller
            )
        }
    }
}
