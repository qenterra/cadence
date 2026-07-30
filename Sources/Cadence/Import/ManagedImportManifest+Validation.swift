import Foundation

extension ManagedImportManifest {
    var allowedNextStates: Set<State> {
        switch state {
        case .prepared:
            [.copied, .rollbackRequired]
        case .copied:
            [.filesCommitted, .rollbackRequired]
        case .filesCommitted:
            [.storeCommitted, .rollbackRequired]
        case .storeCommitted:
            [.complete, .rollbackRequired]
        case .complete, .rollbackRequired:
            []
        }
    }

    func validate(
        entry: Entry
    ) throws {
        try validateMedia(entry)
        try validateLyrics(entry)
        try validateArtwork(entry)
        try validateState(entry)
    }

    func validateMedia(_ entry: Entry) throws {
        let expectedMediaPrefix = "Media/\(entry.trackID.uuidString)."
        guard
            entry.relativeMediaPath.hasPrefix(expectedMediaPrefix),
            entry.relativeMediaPath.split(separator: "/").count == 2,
            SupportedAudioFormat(
                pathExtension: entry.originalExtension
            ) != nil
        else {
            throw ManagedImportManifestError.invalidTargetPath(
                entry.relativeMediaPath
            )
        }
        try validate(hash: entry.expectedAudioHash)
    }

    func validateLyrics(_ entry: Entry) throws {
        guard let lyric = entry.lyric else {
            return
        }
        let expectedPath = "Lyrics/\(entry.trackID.uuidString).lrc"
        guard lyric.relativePath == expectedPath else {
            throw ManagedImportManifestError.invalidTargetPath(
                lyric.relativePath
            )
        }
        if let contentHash = lyric.contentHash {
            try validate(hash: contentHash)
        }
    }

    func validateArtwork(_ entry: Entry) throws {
        guard let artwork = entry.artwork else {
            return
        }
        let expectedPath = "Artwork/Original/\(artwork.id.uuidString)."
            + artwork.format
        guard
            artwork.relativePath == expectedPath,
            artwork.pixelWidth > 0,
            artwork.pixelHeight > 0
        else {
            throw ManagedImportManifestError.invalidTargetPath(
                artwork.relativePath
            )
        }
        try validate(hash: artwork.contentHash)
    }

    func validateState(_ entry: Entry) throws {
        switch entry.state {
        case .pending, .copied:
            guard entry.failureReason == nil else {
                throw ManagedImportManifestError.invalidEntryState(
                    entry.trackID
                )
            }
        case .failed:
            guard entry.failureReason?.isEmpty == false else {
                throw ManagedImportManifestError.invalidEntryState(
                    entry.trackID
                )
            }
        }
    }

    func validate(
        hash: String
    ) throws {
        let isValid = hash.count == 64
            && hash.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "0123456789abcdef")
                    .contains($0)
            }
        guard isValid else {
            throw ManagedImportManifestError.invalidContentHash(hash)
        }
    }

    func insertTarget(
        _ path: String,
        into paths: inout Set<String>
    ) throws {
        guard
            !path.hasPrefix("/"),
            !path.contains("../"),
            !path.contains("/.."),
            !path.contains("//")
        else {
            throw ManagedImportManifestError.invalidTargetPath(path)
        }
        guard paths.insert(path).inserted else {
            throw ManagedImportManifestError.duplicateTargetPath(path)
        }
    }
}
