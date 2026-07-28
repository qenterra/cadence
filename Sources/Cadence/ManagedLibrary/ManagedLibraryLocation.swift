import Foundation

enum ManagedLibraryError: Error, Equatable, LocalizedError, Sendable {
    case musicDirectoryUnavailable
    case invalidRelativePath(String)
    case pathEscapesPackage(String)
    case unsupportedAudioFileExtension(String)
    case layoutCollision(String)

    var errorDescription: String? {
        switch self {
        case .musicDirectoryUnavailable:
            "The current Music directory could not be resolved."
        case let .invalidRelativePath(path):
            "The managed library path is invalid: \(path)"
        case let .pathEscapesPackage(path):
            "The managed library path leaves Cadence.library: \(path)"
        case let .unsupportedAudioFileExtension(fileExtension):
            "Cadence cannot manage the audio extension: \(fileExtension)"
        case let .layoutCollision(path):
            "A file blocks a required managed library directory: \(path)"
        }
    }
}

struct ManagedLibraryLocation: Equatable, Sendable {
    static let packageFilename = "Cadence.library"

    let musicDirectory: URL

    init(musicDirectory: URL) {
        self.musicDirectory = musicDirectory.standardizedFileURL
    }

    static func currentUser(
        fileManager: FileManager = .default
    ) throws -> ManagedLibraryLocation {
        guard let musicDirectory = fileManager.urls(
            for: .musicDirectory,
            in: .userDomainMask
        ).first else {
            throw ManagedLibraryError.musicDirectoryUnavailable
        }
        return ManagedLibraryLocation(musicDirectory: musicDirectory)
    }

    var packageURL: URL {
        musicDirectory.appending(
            path: Self.packageFilename,
            directoryHint: .isDirectory
        )
    }

    func resolve(
        relativePath: String,
        directoryHint: URL.DirectoryHint = .inferFromPath
    ) throws -> URL {
        try validate(relativePath: relativePath)

        let candidate = packageURL
            .appending(path: relativePath, directoryHint: directoryHint)
            .standardizedFileURL
        guard contains(candidate) else {
            throw ManagedLibraryError.pathEscapesPackage(relativePath)
        }
        return candidate
    }

    private func validate(relativePath: String) throws {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.hasSuffix("/")
        else {
            throw ManagedLibraryError.invalidRelativePath(relativePath)
        }

        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard components.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".."
        }) else {
            throw ManagedLibraryError.invalidRelativePath(relativePath)
        }
    }

    private func contains(
        _ candidate: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let package = packageURL.standardizedFileURL
        let candidate = candidate.standardizedFileURL

        guard isSameOrDescendant(candidate, of: package) else {
            return false
        }

        // A destination file normally does not exist yet. Resolving that whole
        // URL can produce a sandbox-specific path representation that differs
        // from the existing package URL, despite the lexical path being valid.
        // Resolve only prefixes that exist (or are symlinks), which still
        // prevents a child symlink from escaping the managed package.
        guard fileManager.fileExists(atPath: package.path) else {
            return true
        }

        let resolvedPackage = package
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let packageComponentCount = package.pathComponents.count
        var prefix = package

        for component in candidate.pathComponents.dropFirst(
            packageComponentCount
        ) {
            prefix = prefix.appending(
                path: component,
                directoryHint: .inferFromPath
            )

            let isSymbolicLink = (
                try? prefix.resourceValues(
                    forKeys: [.isSymbolicLinkKey]
                ).isSymbolicLink
            ) == true
            guard fileManager.fileExists(atPath: prefix.path)
                || isSymbolicLink
            else {
                break
            }

            let resolvedPrefix = prefix
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard isSameOrDescendant(
                resolvedPrefix,
                of: resolvedPackage
            ) else {
                return false
            }
        }

        return true
    }

    private func isSameOrDescendant(
        _ candidate: URL,
        of package: URL
    ) -> Bool {
        let packageComponents = package
            .standardizedFileURL
            .pathComponents
        let candidateComponents = candidate
            .standardizedFileURL
            .pathComponents

        return candidateComponents.count >= packageComponents.count
            && candidateComponents
            .prefix(packageComponents.count)
            .elementsEqual(packageComponents)
    }
}
