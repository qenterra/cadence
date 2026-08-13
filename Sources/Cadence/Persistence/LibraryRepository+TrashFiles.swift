import Foundation

extension LibraryRepository {
    func moveToTrash(
        relativePaths: [String],
        operationID: UUID,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient,
        moved: inout [(original: URL, trashed: URL)]
    ) throws {
        for path in relativePaths {
            let original = try location.resolve(relativePath: path)
            guard fileClient.fileExists(original) else {
                throw LibraryTrashError.missingManagedFile(path)
            }
            let trashPath = "Trash/\(operationID.uuidString)/\(path)"
            let trashed = try location.resolve(relativePath: trashPath)
            try fileClient.createDirectory(
                trashed.deletingLastPathComponent()
            )
            try fileClient.moveItem(original, trashed)
            moved.append((original, trashed))
        }
    }

    func restoreMovedPaths(
        _ moved: [(original: URL, trashed: URL)],
        fileClient: TrashFileClient
    ) -> [String] {
        var failures: [String] = []
        for item in moved.reversed() {
            do {
                try fileClient.createDirectory(
                    item.original.deletingLastPathComponent()
                )
                try fileClient.moveItem(item.trashed, item.original)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        return failures
    }

    func removeTrashOperationDirectory(
        operationID: UUID,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient
    ) throws {
        let directory = trashOperationDirectory(
            operationID: operationID,
            location: location
        )
        guard fileClient.fileExists(directory) else {
            return
        }
        try fileClient.removeItem(directory)
    }

    func trashOperationDirectory(
        operationID: UUID,
        location: ManagedLibraryLocation
    ) -> URL {
        ManagedLibraryPackage(location: location)
            .trashDirectoryURL.appending(
                path: operationID.uuidString,
                directoryHint: .isDirectory
            )
    }
}
