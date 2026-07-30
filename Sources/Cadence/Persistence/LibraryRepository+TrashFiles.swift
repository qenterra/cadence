import Foundation

extension LibraryRepository {
    func moveToTrash(
        relativePaths: [String],
        operationID: UUID,
        location: ManagedLibraryLocation
    ) throws -> [(original: URL, trashed: URL)] {
        var moved: [(original: URL, trashed: URL)] = []
        do {
            for path in relativePaths {
                let original = try location.resolve(relativePath: path)
                guard
                    FileManager.default.fileExists(atPath: original.path)
                else {
                    continue
                }
                let trashPath = "Trash/\(operationID.uuidString)/\(path)"
                let trashed = try location.resolve(relativePath: trashPath)
                try FileManager.default.createDirectory(
                    at: trashed.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: original, to: trashed)
                moved.append((original, trashed))
            }
            return moved
        } catch {
            restoreMovedPaths(moved)
            throw error
        }
    }

    func restoreMovedPaths(
        _ moved: [(original: URL, trashed: URL)]
    ) {
        for item in moved.reversed() {
            try? FileManager.default.createDirectory(
                at: item.original.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.moveItem(
                at: item.trashed,
                to: item.original
            )
        }
    }

    func removeTrashOperationDirectory(
        operationID: UUID,
        location: ManagedLibraryLocation
    ) {
        let directory = ManagedLibraryPackage(location: location)
            .trashDirectoryURL
            .appending(
                path: operationID.uuidString,
                directoryHint: .isDirectory
            )
        try? FileManager.default.removeItem(at: directory)
    }
}
