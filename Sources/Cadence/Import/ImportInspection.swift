import Foundation

struct ImportMetadataIdentity: Hashable, Sendable {
    let normalizedArtist: String
    let normalizedTitle: String

    init(
        artist: String,
        title: String
    ) {
        normalizedArtist = SearchNormalizer.normalize(artist)
        normalizedTitle = SearchNormalizer.normalize(title)
    }

    init(
        normalizedArtist: String,
        normalizedTitle: String
    ) {
        self.normalizedArtist = normalizedArtist
        self.normalizedTitle = normalizedTitle
    }
}

struct ImportDuplicateProbe: Hashable, Sendable {
    let contentHash: String
    let identity: ImportMetadataIdentity
}

struct ImportDuplicateEvidence: Equatable, Sendable {
    let exactHashes: Set<String>
    let metadataIdentities: Set<ImportMetadataIdentity>

    static let empty = ImportDuplicateEvidence(
        exactHashes: [],
        metadataIdentities: []
    )
}

enum ImportDuplicateDisposition: Equatable, Sendable {
    case unique
    case exactDuplicate
    case possibleDuplicate
}

enum ImportLyricsInspection: Equatable, Sendable {
    case unavailable
    case linked(URL)
    case embedded(EmbeddedLyricsPayload)
    case malformed(URL, reason: String)
    case ambiguous([URL])
}

enum ImportInspectionFailure: Equatable, Sendable {
    case unreadableSource(String)
}

struct ImportInspectionDraft: Equatable, Sendable {
    let id: UUID
    let sourceFile: ScannedSourceFile
    let sizeInBytes: Int64
    let metadata: ScannedAudioMetadata?
    let contentHash: String?
    let lyrics: ImportLyricsInspection
    let failure: ImportInspectionFailure?

    init(
        id: UUID = UUID(),
        sourceFile: ScannedSourceFile,
        sizeInBytes: Int64,
        metadata: ScannedAudioMetadata?,
        contentHash: String?,
        lyrics: ImportLyricsInspection,
        failure: ImportInspectionFailure?
    ) {
        self.id = id
        self.sourceFile = sourceFile
        self.sizeInBytes = sizeInBytes
        self.metadata = metadata
        self.contentHash = contentHash
        self.lyrics = lyrics
        self.failure = failure
    }

    var duplicateProbe: ImportDuplicateProbe? {
        guard
            let metadata,
            let contentHash
        else {
            return nil
        }
        return ImportDuplicateProbe(
            contentHash: contentHash,
            identity: ImportMetadataIdentity(
                artist: metadata.artist,
                title: metadata.title
            )
        )
    }
}

struct ImportInspectionCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceFile: ScannedSourceFile
    let sizeInBytes: Int64
    let metadata: ScannedAudioMetadata?
    let contentHash: String?
    let lyrics: ImportLyricsInspection
    let failure: ImportInspectionFailure?
    let duplicateDisposition: ImportDuplicateDisposition

    var sourceFilename: String {
        sourceFile.url.lastPathComponent
    }

    var title: String {
        metadata?.title
            ?? sourceFile.url.deletingPathExtension().lastPathComponent
    }

    var artist: String {
        metadata?.artist ?? "Unknown Artist"
    }

    var album: String {
        metadata?.album ?? "Unknown Album"
    }

    var formatName: String {
        metadata?.container
            ?? sourceFile.url.pathExtension.uppercased()
    }
}

struct DuplicateClassifier: Sendable {
    func classify(
        _ drafts: [ImportInspectionDraft],
        evidence: ImportDuplicateEvidence
    ) -> [ImportInspectionCandidate] {
        var seenHashes: Set<String> = []
        var seenIdentityHashes: [ImportMetadataIdentity: Set<String>] = [:]

        return drafts.map { draft in
            let disposition = disposition(
                for: draft,
                evidence: evidence,
                seenHashes: seenHashes,
                seenIdentityHashes: seenIdentityHashes
            )

            if let probe = draft.duplicateProbe {
                seenHashes.insert(probe.contentHash)
                seenIdentityHashes[probe.identity, default: []]
                    .insert(probe.contentHash)
            }

            return ImportInspectionCandidate(
                id: draft.id,
                sourceFile: draft.sourceFile,
                sizeInBytes: draft.sizeInBytes,
                metadata: draft.metadata,
                contentHash: draft.contentHash,
                lyrics: draft.lyrics,
                failure: draft.failure,
                duplicateDisposition: disposition
            )
        }
    }

    private func disposition(
        for draft: ImportInspectionDraft,
        evidence: ImportDuplicateEvidence,
        seenHashes: Set<String>,
        seenIdentityHashes: [ImportMetadataIdentity: Set<String>]
    ) -> ImportDuplicateDisposition {
        guard
            draft.failure == nil,
            let probe = draft.duplicateProbe
        else {
            return .unique
        }

        let isExactDuplicate = evidence.exactHashes.contains(
            probe.contentHash
        ) || seenHashes.contains(probe.contentHash)
        if isExactDuplicate {
            return .exactDuplicate
        }

        let batchIdentityHashes = seenIdentityHashes[probe.identity] ?? []
        let hasDifferentBatchHash = batchIdentityHashes.contains {
            $0 != probe.contentHash
        }
        let isPossibleDuplicate = evidence.metadataIdentities.contains(
            probe.identity
        ) || hasDifferentBatchHash
        if isPossibleDuplicate {
            return .possibleDuplicate
        }

        return .unique
    }
}

extension ImportInspectionCandidate {
    var preview: ImportCandidatePreview {
        ImportCandidatePreview(
            id: id.uuidString,
            sourceTrackID: nil,
            sourceFilename: sourceFilename,
            title: title,
            artist: artist,
            album: album,
            format: formatName,
            sizeInBytes: sizeInBytes,
            lyricStatus: previewLyricStatus,
            classification: previewClassification
        )
    }

    private var previewLyricStatus: ImportLyricStatus {
        switch lyrics {
        case .unavailable:
            .unavailable
        case .linked, .embedded:
            .linked
        case .malformed:
            .malformed
        case .ambiguous:
            .ambiguous
        }
    }

    private var previewClassification: ImportCandidateClassification {
        if failure != nil {
            return .issue(.unreadableSource)
        }

        switch duplicateDisposition {
        case .exactDuplicate:
            return .exactDuplicate
        case .possibleDuplicate:
            return .possibleDuplicate
        case .unique:
            break
        }

        switch lyrics {
        case .malformed:
            return .issue(.malformedLyrics)
        case .ambiguous:
            return .issue(.ambiguousLyrics)
        case .unavailable, .linked, .embedded:
            return .ready
        }
    }
}
