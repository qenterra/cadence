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
    struct UnsupportedFile: Equatable, Sendable {
        let url: URL
        let relativePath: String
    }

    struct Result: Equatable, Sendable {
        let files: [ScannedSourceFile]
        let unsupportedFiles: [UnsupportedFile]
    }

    func scan(
        source: ImportSource
    ) async throws -> [ScannedSourceFile] {
        try await scanResult(source: source).files
    }

    func scanResult(source: ImportSource) async throws -> Result {
        try Task.checkCancellation()

        var files: [ScannedSourceFile] = []
        var unsupportedFiles: [UnsupportedFile] = []
        for root in source.urls.sorted(by: urlComesBefore) {
            try Task.checkCancellation()
            let result = try scan(root: root)
            files.append(contentsOf: result.files)
            unsupportedFiles.append(contentsOf: result.unsupportedFiles)
        }

        files.sort {
            if $0.relativePath != $1.relativePath {
                return $0.relativePath < $1.relativePath
            }
            return $0.url.path < $1.url.path
        }
        unsupportedFiles.sort {
            if $0.relativePath != $1.relativePath {
                return $0.relativePath < $1.relativePath
            }
            return $0.url.path < $1.url.path
        }
        return Result(files: files, unsupportedFiles: unsupportedFiles)
    }

    private func scan(
        root: URL
    ) throws -> Result {
        let values = try root.resourceValues(
            forKeys: resourceKeys
        )
        guard values.isSymbolicLink != true else {
            return Result(files: [], unsupportedFiles: [])
        }

        if values.isRegularFile == true {
            let relativePath = root.lastPathComponent
            if let candidate = candidate(
                url: root,
                relativePath: relativePath
            ) {
                return Result(files: [candidate], unsupportedFiles: [])
            }
            return Result(
                files: [],
                unsupportedFiles: unsupportedFile(url: root, relativePath: relativePath).map { [$0] } ?? []
            )
        }

        guard values.isDirectory == true else {
            return Result(files: [], unsupportedFiles: [])
        }

        return try scanDirectory(root)
    }

    private func scanDirectory(
        _ root: URL
    ) throws -> Result {
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
        var unsupportedFiles: [UnsupportedFile] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: resourceKeys)

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
            } else if let unsupported = unsupportedFile(
                url: url,
                relativePath: relativePath
            ) {
                unsupportedFiles.append(unsupported)
            }
        }

        if let enumerationError {
            throw SourceScannerError.unreadableSource(
                "\(root.path): \(enumerationError.localizedDescription)"
            )
        }
        return Result(files: files, unsupportedFiles: unsupportedFiles)
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

    private func unsupportedFile(
        url: URL,
        relativePath: String
    ) -> UnsupportedFile? {
        let pathExtension = url.pathExtension.lowercased()
        guard !pathExtension.isEmpty, !ignoredSidecarExtensions.contains(pathExtension) else {
            return nil
        }
        return UnsupportedFile(url: url, relativePath: relativePath)
    }

    private var ignoredSidecarExtensions: Set<String> {
        ["jpg", "jpeg", "png", "webp", "gif", "heic", "txt", "pdf", "cue", "nfo", "m3u", "m3u8"]
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
