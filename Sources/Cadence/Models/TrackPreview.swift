import Foundation

struct TrackPreview: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let discNumber: Int
    let trackNumber: Int
    let year: Int
    let format: String
    let bitDepth: Int
    let sampleRate: Double
    let duration: TimeInterval
    let fileSize: String
    let lastPlayed: Date?
    let rating: Int
    let isFavorite: Bool
    let artworkPalette: ArtworkPalette?

    var artistID: String {
        artist
    }

    var albumID: String {
        "\(artist)\u{1F}\(album)"
    }

    var durationText: String {
        Self.timeText(duration)
    }

    var yearText: String {
        year.formatted(.number.grouping(.never))
    }

    var libraryPreviewMetadataText: String {
        "\(album) · \(yearText) · \(durationText) · \(format)"
    }

    static func timeText(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time.rounded()), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

enum ArtworkPalette: String, Hashable, Sendable {
    case amberNoir
    case arctic
    case blueHour
    case ember
    case forest
    case lilac
    case ocean
    case rose
    case silver
    case sunset
}
