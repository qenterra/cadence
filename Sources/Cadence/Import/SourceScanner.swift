import Foundation

enum SourceScannerError: Error, LocalizedError, Sendable {
    case unreadableSource(String)

    var errorDescription: String? {
        switch self {
        case let .unreadableSource(path):
            "Cadence could not read the import source: \(path)"
        }
    }
}

struct SourceScanner: Sendable {
    func scan(
        source: ImportSource
    ) async throws -> [ScannedSourceFile] {
        try Task.checkCancellation()

        var files: [ScannedSourceFile] = []
        for root in source.urls.sorted(by: urlComesBefore) {
            try Task.checkCancellation()
            try files.append(contentsOf: scan(root: root))
        }

        return files.sorted {
            if $0.relativePath != $1.relativePath {
                return $0.relativePath < $1.relativePath
            }
            return $0.url.path < $1.url.path
        }
    }

    private func scan(
        root: URL
    ) throws -> [ScannedSourceFile] {
        let values = try root.resourceValues(
            forKeys: resourceKeys
        )
        guard values.isSymbolicLink != true else {
            return []
        }

        if values.isRegularFile == true {
            return candidate(
                url: root,
                relativePath: root.lastPathComponent
            ).map { [$0] } ?? []
        }

        guard values.isDirectory == true else {
            return []
        }

        return try scanDirectory(root)
    }

    private func scanDirectory(
        _ root: URL
    ) throws -> [ScannedSourceFile] {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw SourceScannerError.unreadableSource(root.path)
        }

        var files: [ScannedSourceFile] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try url.resourceValues(
                forKeys: resourceKeys
            )

            if shouldSkip(
                url: url,
                values: values,
                enumerator: enumerator
            ) {
                continue
            }

            guard values.isRegularFile == true else {
                continue
            }

            let relativePath = relativePath(
                from: root,
                to: url
            )
            if let candidate = candidate(
                url: url,
                relativePath: relativePath
            ) {
                files.append(candidate)
            }
        }

        if let enumerationError {
            throw SourceScannerError.unreadableSource(
                "\(root.path): \(enumerationError.localizedDescription)"
            )
        }
        return files
    }

    private func shouldSkip(
        url: URL,
        values: URLResourceValues,
        enumerator: FileManager.DirectoryEnumerator
    ) -> Bool {
        if values.isSymbolicLink == true {
            if values.isDirectory == true {
                enumerator.skipDescendants()
            }
            return true
        }

        guard values.isDirectory == true else {
            return false
        }
        if url.lastPathComponent.caseInsensitiveCompare(
            ManagedLibraryLocation.packageFilename
        ) == .orderedSame {
            enumerator.skipDescendants()
        }
        return true
    }

    private func candidate(
        url: URL,
        relativePath: String
    ) -> ScannedSourceFile? {
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "lrc" {
            return ScannedSourceFile(
                url: url,
                relativePath: relativePath,
                kind: .lyrics
            )
        }
        guard let format = SupportedAudioFormat(
            pathExtension: pathExtension
        ) else {
            return nil
        }
        return ScannedSourceFile(
            url: url,
            relativePath: relativePath,
            kind: .audio(format)
        )
    }

    private func relativePath(
        from root: URL,
        to file: URL
    ) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return file.lastPathComponent
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func urlComesBefore(
        _ lhs: URL,
        _ rhs: URL
    ) -> Bool {
        lhs.path < rhs.path
    }

    private var resourceKeys: Set<URLResourceKey> {
        [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
    }
}
