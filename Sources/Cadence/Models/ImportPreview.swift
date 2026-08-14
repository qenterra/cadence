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
            String(localized: "Empty")
        case .scanning:
            String(localized: "Scanning")
        case .review:
            String(localized: "Review")
        case .importing:
            String(localized: "Importing")
        case .complete:
            String(localized: "Complete")
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
            String(localized: "Ready")
        case .duplicates:
            String(localized: "Duplicates")
        case .issues:
            String(localized: "Issues")
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
            String(localized: "LRC linked")
        case .unavailable:
            String(localized: "No lyrics")
        case .malformed:
            String(localized: "Invalid LRC")
        case .ambiguous:
            String(localized: "LRC conflict")
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
            String(localized: "Unsupported format")
        case .unreadableSource:
            String(localized: "File unavailable")
        case .malformedLyrics:
            String(localized: "Lyrics will be skipped")
        case .ambiguousLyrics:
            String(localized: "Choose lyrics later")
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
            String(localized: "Ready")
        case .exactDuplicate:
            String(localized: "Already in Library")
        case .possibleDuplicate:
            String(localized: "Possible Duplicate")
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
