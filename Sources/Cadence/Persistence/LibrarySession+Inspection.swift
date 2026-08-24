import Foundation

enum ExistingLibraryPackageInspection {
    case absent
    case valid
    case failed(LibrarySessionFailure)
}

extension LibrarySession {
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
        do {
            let identity = try package.readIdentity()
            let localCatalog = try LocalLibraryCatalogLocation.currentUser(
                identity: identity,
                fileManager: fileManager
            )
            guard fileManager.fileExists(atPath: localCatalog.storeURL.path)
                || fileManager.fileExists(atPath: package.metadataStoreURL.path)
            else {
                return .failed(
                    LibrarySessionFailure(
                        kind: .missingMetadataStore,
                        message: "The local Cadence catalog is missing.",
                        revealURL: localCatalog.rootURL
                    )
                )
            }
            return .valid
        } catch {
            return .failed(
                LibrarySessionFailure(
                    kind: .unreadableIdentity,
                    message: "The Cadence folder has an unreadable library identity.",
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
