import Foundation

struct LibraryRelocationRecoveryResult: Equatable, Sendable {
    let recoveredOperationIDs: [UUID]
    let cleanupFailures: [UUID]

    static let empty = LibraryRelocationRecoveryResult(
        recoveredOperationIDs: [],
        cleanupFailures: []
    )
}

actor LibraryRelocationRecovery {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func recover(
        activeLocation: ManagedLibraryLocation
    ) -> LibraryRelocationRecoveryResult {
        let manifestURLs = candidateManifestURLs(
            activeLocation: activeLocation
        )
        var manifests: [UUID: LibraryRelocationManifest] = [:]
        for url in manifestURLs {
            guard
                let data = try? Data(contentsOf: url),
                let manifest = try? JSONDecoder().decode(
                    LibraryRelocationManifest.self,
                    from: data
                )
            else {
                continue
            }
            manifests[manifest.operationID] = manifest
        }
        guard !manifests.isEmpty else {
            return .empty
        }

        var recovered: [UUID] = []
        var failures: [UUID] = []
        for manifest in manifests.values {
            if recover(
                manifest,
                activeLocation: activeLocation
            ) {
                recovered.append(manifest.operationID)
            } else {
                failures.append(manifest.operationID)
            }
        }
        return LibraryRelocationRecoveryResult(
            recoveredOperationIDs: recovered.sorted { $0.uuidString < $1.uuidString },
            cleanupFailures: failures.sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func recover(
        _ manifest: LibraryRelocationManifest,
        activeLocation: ManagedLibraryLocation
    ) -> Bool {
        let activePath = canonicalPath(activeLocation.packageURL)
        let sourceURL = URL(filePath: manifest.sourcePackagePath)
        let destinationURL = URL(filePath: manifest.destinationPackagePath)
        let sourcePath = canonicalPath(sourceURL)
        let destinationPath = canonicalPath(destinationURL)
        let destinationParent = destinationURL.deletingLastPathComponent()
        let stagingURL = destinationParent.appending(
            path: ".Cadence-relocation-\(manifest.operationID.uuidString)",
            directoryHint: .isDirectory
        )
        let destinationManifestURL = destinationParent.appending(
            path: ".Cadence-relocation-\(manifest.operationID.uuidString).json"
        )
        let sourceManifestURL = sourceURL
            .appending(path: "Staging/Relocations", directoryHint: .isDirectory)
            .appending(path: "\(manifest.operationID.uuidString).json")

        if fileManager.fileExists(atPath: stagingURL.path) {
            try? fileManager.removeItem(at: stagingURL)
        }

        let cleanupTarget: URL?
        if activePath == destinationPath {
            cleanupTarget = fileManager.fileExists(atPath: sourceURL.path)
                ? sourceURL
                : nil
        } else if activePath == sourcePath {
            cleanupTarget = fileManager.fileExists(atPath: destinationURL.path)
                ? destinationURL
                : nil
        } else {
            return false
        }

        if let cleanupTarget {
            do {
                var trashedURL: NSURL?
                try fileManager.trashItem(
                    at: cleanupTarget,
                    resultingItemURL: &trashedURL
                )
            } catch {
                return false
            }
        }
        try? fileManager.removeItem(at: destinationManifestURL)
        try? fileManager.removeItem(at: sourceManifestURL)
        return true
    }

    private func candidateManifestURLs(
        activeLocation: ManagedLibraryLocation
    ) -> [URL] {
        let package = ManagedLibraryPackage(location: activeLocation)
        let sourceDirectory = package.stagingDirectoryURL.appending(
            path: "Relocations",
            directoryHint: .isDirectory
        )
        let sourceManifests = (
            try? fileManager.contentsOfDirectory(
                at: sourceDirectory,
                includingPropertiesForKeys: nil
            )
        ) ?? []
        let parentManifests = (
            try? fileManager.contentsOfDirectory(
                at: activeLocation.musicDirectory,
                includingPropertiesForKeys: nil
            )
        )?.filter {
            $0.lastPathComponent.hasPrefix(".Cadence-relocation-")
                && $0.pathExtension == "json"
        } ?? []
        return sourceManifests + parentManifests
    }

    private func canonicalPath(
        _ url: URL
    ) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
