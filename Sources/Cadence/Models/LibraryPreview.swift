import Foundation

struct ArtistPreview: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let albumCount: Int
    let trackCount: Int
}

struct AlbumPreview: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let year: Int
    let trackCount: Int
    let totalDuration: TimeInterval
    let artworkPalette: ArtworkPalette?
    let genres: [String]

    var yearText: String {
        year.formatted(.number.grouping(.never))
    }
}
