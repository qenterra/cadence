@testable import Cadence

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
