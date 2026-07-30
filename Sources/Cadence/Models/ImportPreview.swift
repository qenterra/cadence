import Foundation

enum ImportPreviewStage: String, CaseIterable, Identifiable, Sendable {
    case empty
    case scanning
    case review
    case importing
    case complete

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .empty:
            "Empty"
        case .scanning:
            "Scanning"
        case .review:
            "Review"
        case .importing:
            "Importing"
        case .complete:
            "Complete"
        }
    }
}

enum ImportReviewCategory: String, CaseIterable, Identifiable, Sendable {
    case ready
    case duplicates
    case issues

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .ready:
            "Ready"
        case .duplicates:
            "Duplicates"
        case .issues:
            "Issues"
        }
    }
}

enum ImportLyricStatus: String, Hashable, Sendable {
    case linked
    case unavailable
    case malformed
    case ambiguous

    var title: String {
        switch self {
        case .linked:
            "LRC linked"
        case .unavailable:
            "No lyrics"
        case .malformed:
            "Invalid LRC"
        case .ambiguous:
            "LRC conflict"
        }
    }

    var symbolName: String {
        switch self {
        case .linked:
            "text.badge.checkmark"
        case .unavailable:
            "text.badge.xmark"
        case .malformed:
            "exclamationmark.bubble"
        case .ambiguous:
            "arrow.triangle.branch"
        }
    }
}

enum ImportPreviewIssue: String, Hashable, Sendable {
    case unsupportedFormat
    case unreadableSource
    case malformedLyrics
    case ambiguousLyrics

    var title: String {
        switch self {
        case .unsupportedFormat:
            "Unsupported format"
        case .unreadableSource:
            "File unavailable"
        case .malformedLyrics:
            "Lyrics will be skipped"
        case .ambiguousLyrics:
            "Choose lyrics later"
        }
    }

    var blocksAudio: Bool {
        switch self {
        case .unsupportedFormat, .unreadableSource:
            true
        case .malformedLyrics, .ambiguousLyrics:
            false
        }
    }
}

enum ImportCandidateClassification: Hashable, Sendable {
    case ready
    case exactDuplicate
    case possibleDuplicate
    case issue(ImportPreviewIssue)

    var reviewCategory: ImportReviewCategory {
        switch self {
        case .ready:
            .ready
        case .exactDuplicate, .possibleDuplicate:
            .duplicates
        case .issue:
            .issues
        }
    }

    var isEligible: Bool {
        switch self {
        case .ready, .possibleDuplicate:
            true
        case .exactDuplicate:
            false
        case let .issue(issue):
            !issue.blocksAudio
        }
    }

    var isIncludedByDefault: Bool {
        self == .ready || self == .issue(.malformedLyrics)
    }

    var title: String {
        switch self {
        case .ready:
            "Ready"
        case .exactDuplicate:
            "Already in Library"
        case .possibleDuplicate:
            "Possible Duplicate"
        case let .issue(issue):
            issue.title
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            "checkmark"
        case .exactDuplicate:
            "equal"
        case .possibleDuplicate:
            "rectangle.on.rectangle"
        case let .issue(issue):
            issue.blocksAudio
                ? "exclamationmark.triangle"
                : "exclamationmark.circle"
        }
    }
}

struct ImportCandidatePreview: Identifiable, Hashable, Sendable {
    let id: String
    let sourceTrackID: TrackPreview.ID?
    let sourceFilename: String
    let title: String
    let artist: String
    let album: String
    let format: String
    let sizeInBytes: Int64
    let lyricStatus: ImportLyricStatus
    let classification: ImportCandidateClassification

    var isEligible: Bool {
        classification.isEligible
    }

    var isIncludedByDefault: Bool {
        classification.isIncludedByDefault
    }

    var fileSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: sizeInBytes,
            countStyle: .file
        )
    }
}

enum ImportCandidateSelectionIntent: Sendable {
    case replace
    case toggle
    case range
}

struct ImportPreviewSummary: Equatable, Sendable {
    let importedTrackCount: Int
    let linkedLyricsCount: Int
    let exactDuplicateCount: Int
    let issueCount: Int
    let importedSizeInBytes: Int64

    var importedSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: importedSizeInBytes,
            countStyle: .file
        )
    }
}

extension [ImportCandidatePreview] {
    static let mockImportCandidates: Self = [
        ImportCandidatePreview(
            id: "midnight-static",
            sourceTrackID: 1,
            sourceFilename: "Midnight Static.flac",
            title: "Midnight Static",
            artist: "North Assembly",
            album: "Signals After Dark",
            format: "FLAC",
            sizeInBytes: 94_000_000,
            lyricStatus: .linked,
            classification: .ready
        ),
        ImportCandidatePreview(
            id: "glass-horizon",
            sourceTrackID: 2,
            sourceFilename: "Glass Horizon.flac",
            title: "Glass Horizon",
            artist: "North Assembly",
            album: "Signals After Dark",
            format: "FLAC",
            sizeInBytes: 87_000_000,
            lyricStatus: .unavailable,
            classification: .ready
        ),
        ImportCandidatePreview(
            id: "quiet-return",
            sourceTrackID: 10,
            sourceFilename: "Quiet Return.m4a",
            title: "Quiet Return",
            artist: "North Assembly",
            album: "Signals After Dark",
            format: "ALAC",
            sizeInBytes: 76_000_000,
            lyricStatus: .linked,
            classification: .ready
        ),
        ImportCandidatePreview(
            id: "coastal-machine",
            sourceTrackID: 18,
            sourceFilename: "Coastal Machine.aiff",
            title: "Coastal Machine",
            artist: "Coastal Machines",
            album: "Tidal Memory",
            format: "AIFF",
            sizeInBytes: 112_000_000,
            lyricStatus: .unavailable,
            classification: .ready
        ),
        ImportCandidatePreview(
            id: "exact-night-drive",
            sourceTrackID: 11,
            sourceFilename: "Night Drive.flac",
            title: "Night Drive",
            artist: "North Assembly",
            album: "Midnight Static",
            format: "FLAC",
            sizeInBytes: 91_000_000,
            lyricStatus: .linked,
            classification: .exactDuplicate
        ),
        ImportCandidatePreview(
            id: "possible-afterimage",
            sourceTrackID: 5,
            sourceFilename: "Afterimage (2026 Remaster).flac",
            title: "Afterimage",
            artist: "North Assembly",
            album: "Signals After Dark",
            format: "FLAC",
            sizeInBytes: 104_000_000,
            lyricStatus: .unavailable,
            classification: .possibleDuplicate
        ),
        ImportCandidatePreview(
            id: "malformed-falling-signals",
            sourceTrackID: 8,
            sourceFilename: "Falling Signals.flac",
            title: "Falling Signals",
            artist: "North Assembly",
            album: "Signals After Dark",
            format: "FLAC",
            sizeInBytes: 89_000_000,
            lyricStatus: .malformed,
            classification: .issue(.malformedLyrics)
        ),
        ImportCandidatePreview(
            id: "ambiguous-blue-hours",
            sourceTrackID: 31,
            sourceFilename: "Blue Hours.flac",
            title: "Blue Hours",
            artist: "Kite Theory",
            album: "Nocturnes for Empty Roads",
            format: "FLAC",
            sizeInBytes: 97_000_000,
            lyricStatus: .ambiguous,
            classification: .issue(.ambiguousLyrics)
        ),
        ImportCandidatePreview(
            id: "unsupported-demo",
            sourceTrackID: nil,
            sourceFilename: "Basement Demo.ogg",
            title: "Basement Demo",
            artist: "Unknown Artist",
            album: "Unknown Album",
            format: "OGG",
            sizeInBytes: 24_000_000,
            lyricStatus: .unavailable,
            classification: .issue(.unsupportedFormat)
        ),
        ImportCandidatePreview(
            id: "unreadable-archive",
            sourceTrackID: nil,
            sourceFilename: "Archive Master.wav",
            title: "Archive Master",
            artist: "Unknown Artist",
            album: "Unknown Album",
            format: "WAV",
            sizeInBytes: 182_000_000,
            lyricStatus: .unavailable,
            classification: .issue(.unreadableSource)
        ),
    ]
}
