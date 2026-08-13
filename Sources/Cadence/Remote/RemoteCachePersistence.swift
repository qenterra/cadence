import Foundation

enum RemoteCachePersistence {
    static func loadIndex(
        from url: URL,
        fileManager: FileManager
    ) throws -> RemoteCacheIndex {
        guard fileManager.fileExists(atPath: url.path) else {
            return RemoteCacheIndex()
        }
        do {
            let data = try Data(contentsOf: url)
            let index = try JSONDecoder().decode(
                RemoteCacheIndex.self,
                from: data
            )
            guard index.schemaVersion == RemoteCacheIndex.currentSchemaVersion,
                  index.entries.allSatisfy({ validRelativePath($0.relativePath) })
            else {
                throw RemoteCacheError.corruptIndex(url, nil)
            }
            return index
        } catch let error as RemoteCacheError {
            throw error
        } catch {
            throw RemoteCacheError.corruptIndex(url, error)
        }
    }

    static func removeAbandonedStagingFiles(
        at url: URL,
        fileManager: FileManager
    ) throws {
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw RemoteCacheError.stagingCleanupFailed(url, error, nil)
        }
        for file in files {
            do {
                try fileManager.removeItem(at: file)
            } catch {
                throw RemoteCacheError.stagingCleanupFailed(file, error, nil)
            }
        }
    }

    static func removeStagedFileIfPresent(
        _ url: URL,
        fileManager: FileManager,
        primaryError: Error?
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw RemoteCacheError.stagingCleanupFailed(
                url,
                error,
                primaryError
            )
        }
    }

    static func rollbackPromotion(
        destinationExisted: Bool,
        destinationURL: URL,
        stagedURL: URL,
        fileManager: FileManager,
        primaryError: Error
    ) throws {
        if !destinationExisted,
           fileManager.fileExists(atPath: destinationURL.path) {
            do {
                try fileManager.removeItem(at: destinationURL)
            } catch let rollbackError {
                throw RemoteCacheError.promotionRollbackFailed(
                    destinationURL,
                    primaryError,
                    rollbackError
                )
            }
        }
        try removeStagedFileIfPresent(
            stagedURL,
            fileManager: fileManager,
            primaryError: primaryError
        )
    }

    private static func validRelativePath(
        _ path: String
    ) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.count == 2
            && components[0] == "Objects"
            && !components[1].isEmpty
            && components[1] != "."
            && components[1] != ".."
    }
}
