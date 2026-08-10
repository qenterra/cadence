@testable import Cadence
import Foundation
import Testing

struct AlbumsListeningDomainTests {
    @Test("Album sorting uses approved defaults and deterministic ties")
    func sorting() {
        let first = album(
            id: "a",
            title: "Échoes",
            artist: "Beta",
            year: 2024
        )
        let second = album(
            id: "b",
            title: "echoes",
            artist: "Alpha",
            year: 2026
        )
        let third = album(
            id: "c",
            title: "After",
            artist: "Alpha",
            year: 2025
        )
        let albums = [first, second, third]

        #expect(sortedIDs(albums, descriptor: .allAlbums) == ["c", "b", "a"])
        #expect(
            sortedIDs(
                albums,
                descriptor: .defaultDescriptor(for: .title)
            ) == ["c", "a", "b"]
        )
        #expect(
            sortedIDs(
                albums,
                descriptor: .defaultDescriptor(for: .releaseYear)
            ) == ["b", "c", "a"]
        )
    }

    @Test("Favorite recency is independent from normal album sorting")
    func favoriteRecency() {
        let albums = [
            album(id: "a", title: "A", artist: "A"),
            album(id: "b", title: "B", artist: "B"),
        ]
        let favoriteDates = ["a": date(100), "b": date(200)]

        let sorted = AlbumListeningProjection.sortedAlbums(
            albums,
            by: .recentlyFavorited,
            favoriteDates: favoriteDates
        )

        #expect(sorted.map(\.id) == ["b", "a"])
        #expect(sortedIDs(albums, descriptor: .allAlbums) == ["a", "b"])
    }

    @Test("Shelf projection reports exact fit and overflow")
    func shelfProjection() {
        let albums = (1 ... 4).map {
            album(id: "\($0)", title: "\($0)", artist: "Artist")
        }

        let empty = AlbumListeningProjection.shelf(albums, capacity: 0)
        #expect(empty.albums.isEmpty)
        #expect(empty.hasOverflow)

        let exact = AlbumListeningProjection.shelf(albums, capacity: 4)
        #expect(exact.albums.count == 4)
        #expect(!exact.hasOverflow)

        let overflow = AlbumListeningProjection.shelf(albums, capacity: 2)
        #expect(overflow.albums.map(\.id) == ["1", "2"])
        #expect(overflow.hasOverflow)
    }

    @Test("Canonical album tracks use disc, track, and ID order")
    func canonicalTracks() {
        let tracks = [
            track(id: 5, disc: 2, number: 1),
            track(id: 3, disc: 1, number: 2),
            track(id: 2, disc: 1, number: 1),
            track(id: 1, disc: 1, number: 1),
        ]

        #expect(
            AlbumListeningProjection.canonicalTracks(tracks).map(\.id)
                == [1, 2, 3, 5]
        )
    }

    @Test("Album search uses album identity and accepted album tags only")
    func search() throws {
        let item = album(
            id: "album",
            title: "Signals After Dark",
            artist: "North Assembly"
        )
        let tag = try #require(TagPreview(path: "mood/nocturnal"))

        #expect(
            AlbumListeningProjection.matchesSearch(
                album: item,
                query: "signals",
                assignedTags: []
            )
        )
        #expect(
            AlbumListeningProjection.matchesSearch(
                album: item,
                query: "north",
                assignedTags: []
            )
        )
        #expect(
            AlbumListeningProjection.matchesSearch(
                album: item,
                query: "mood/nocturnal",
                assignedTags: [tag]
            )
        )
        #expect(
            !AlbumListeningProjection.matchesSearch(
                album: item,
                query: "unrelated track title",
                assignedTags: [tag]
            )
        )
    }

    @Test("Adaptive album metrics stay readable at supported widths")
    func layoutMetrics() {
        let minimum = AlbumsLayoutMetrics(totalWidth: 1005)
        let standard = AlbumsLayoutMetrics(totalWidth: 1440)
        let wide = AlbumsLayoutMetrics(totalWidth: 1900)

        #expect(minimum.columnCount == 5)
        #expect(standard.columnCount == 8)
        #expect(wide.columnCount > standard.columnCount)
        #expect(minimum.tileWidth >= AlbumsLayoutMetrics.minimumTileWidth)
        #expect(standard.tileWidth <= AlbumsLayoutMetrics.maximumTileWidth)
        #expect(minimum.shelfCapacity == minimum.columnCount)
    }

    @Test("Detail and table metrics protect artwork and title")
    func detailMetrics() {
        #expect(AlbumDetailLayoutMetrics(totalWidth: 1005).artworkSize == 180)
        #expect(AlbumDetailLayoutMetrics(totalWidth: 1440).artworkSize == 220)

        let columns = AlbumTrackTableColumnWidths(totalWidth: 900)
        #expect(columns.title >= 180)
        #expect(abs(columns.total - 900) < 0.001)
    }
}

private extension AlbumsListeningDomainTests {
    func sortedIDs(
        _ albums: [AlbumPreview],
        descriptor: AlbumSortDescriptor
    ) -> [AlbumPreview.ID] {
        AlbumListeningProjection.sortedAlbums(
            albums,
            by: descriptor
        )
        .map(\.id)
    }

    func album(
        id: String,
        title: String,
        artist: String,
        year: Int = 2026
    ) -> AlbumPreview {
        AlbumPreview(
            id: id,
            title: title,
            artist: artist,
            year: year,
            trackCount: 1,
            totalDuration: 240,
            artworkPalette: .silver,
            genres: []
        )
    }

    func track(
        id: Int,
        disc: Int,
        number: Int
    ) -> TrackPreview {
        TrackPreview(
            id: id,
            title: "Track \(id)",
            artist: "Artist",
            album: "Album",
            discNumber: disc,
            trackNumber: number,
            year: 2026,
            format: "FLAC",
            bitDepth: 24,
            sampleRate: 96,
            duration: 240,
            fileSize: "80 MB",
            lastPlayed: nil,
            rating: 5,
            isFavorite: false,
            artworkPalette: .silver
        )
    }

    func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
