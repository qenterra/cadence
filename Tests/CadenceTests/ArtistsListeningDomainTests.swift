@testable import Cadence
import Foundation
import Testing

struct ArtistsListeningDomainTests {
    @Test("Owned releases are classified while credited releases appear separately")
    func releaseOwnershipSections() {
        let artistID = UUID()
        let otherArtistID = UUID()
        let single = release(
            title: "Signal",
            artistID: artistID,
            year: 2026,
            kind: .single
        )
        let ep = release(
            title: "Night Drive",
            artistID: artistID,
            year: 2025,
            kind: .ep
        )
        let album = release(
            title: "Static",
            artistID: artistID,
            year: 2024,
            kind: .album
        )
        let featured = release(
            title: "Guest Signal",
            artistID: otherArtistID,
            year: 2027,
            kind: .album
        )

        let sections = ArtistReleaseSections.build(
            artistID: artistID,
            releases: [album, featured, single, ep]
        )

        #expect(sections.singles.map(\.id) == [single.id])
        #expect(sections.eps.map(\.id) == [ep.id])
        #expect(sections.albums.map(\.id) == [album.id])
        #expect(sections.appearsOn.map(\.id) == [featured.id])
    }

    @Test("Artist sorting uses approved defaults and deterministic ties")
    func sorting() {
        let artists = [
            artist(id: "b", name: "Écho", albums: 1, tracks: 2),
            artist(id: "a", name: "echo", albums: 3, tracks: 1),
            artist(id: "c", name: "After", albums: 2, tracks: 4),
        ]
        let recentDates = [
            "a": date(100),
            "b": date(300),
            "c": date(200),
        ]

        #expect(
            sortedIDs(
                artists,
                descriptor: .allArtists,
                recentDates: recentDates
            ) == ["c", "a", "b"]
        )
        #expect(
            sortedIDs(
                artists,
                descriptor: .recentlyPlayed,
                recentDates: recentDates
            ) == ["b", "c", "a"]
        )
        #expect(
            sortedIDs(
                artists,
                descriptor: .defaultDescriptor(for: .albumCount),
                recentDates: recentDates
            ) == ["a", "c", "b"]
        )
        #expect(
            sortedIDs(
                artists,
                descriptor: .defaultDescriptor(for: .trackCount),
                recentDates: recentDates
            ) == ["c", "b", "a"]
        )
    }

    @Test("Recent playback uses the newest played track")
    func recentPlayback() {
        let tracks = [
            track(id: 1, lastPlayed: date(100)),
            track(id: 2, lastPlayed: nil),
            track(id: 3, lastPlayed: date(300)),
        ]

        #expect(
            ArtistListeningProjection.mostRecentPlayback(in: tracks)
                == date(300)
        )
        #expect(
            ArtistListeningProjection.mostRecentPlayback(
                in: [track(id: 4, lastPlayed: nil)]
            ) == nil
        )
    }

    @Test("Artist shelf reports exact fit and overflow")
    func shelfProjection() {
        let artists = (1 ... 4).map {
            artist(id: "\($0)", name: "\($0)")
        }

        let empty = ArtistListeningProjection.shelf(artists, capacity: 0)
        #expect(empty.artists.isEmpty)
        #expect(empty.hasOverflow)

        let exact = ArtistListeningProjection.shelf(artists, capacity: 4)
        #expect(exact.artists.count == 4)
        #expect(!exact.hasOverflow)

        let overflow = ArtistListeningProjection.shelf(artists, capacity: 2)
        #expect(overflow.artists.map(\.id) == ["1", "2"])
        #expect(overflow.hasOverflow)
    }

    @Test("Canonical artist tracks use year, album, disc, track, and ID")
    func canonicalTracks() {
        let tracks = [
            track(id: 5, album: "B", year: 2025, disc: 1, number: 1),
            track(id: 3, album: "A", year: 2025, disc: 2, number: 1),
            track(id: 2, album: "A", year: 2025, disc: 1, number: 2),
            track(id: 1, album: "A", year: 2025, disc: 1, number: 1),
            track(id: 4, album: "Z", year: 2024, disc: 1, number: 1),
        ]

        #expect(
            ArtistListeningProjection.canonicalTracks(tracks).map(\.id)
                == [4, 1, 2, 3, 5]
        )
    }

    @Test("Artist search uses artist identity and derived tags")
    func search() throws {
        let item = artist(id: "north", name: "North Assembly")
        let tag = try #require(TagPreview(path: "mood/nocturnal"))

        #expect(
            ArtistListeningProjection.matchesSearch(
                artist: item,
                query: "north",
                derivedTags: []
            )
        )
        #expect(
            ArtistListeningProjection.matchesSearch(
                artist: item,
                query: "mood/nocturnal",
                derivedTags: [tag]
            )
        )
        #expect(
            !ArtistListeningProjection.matchesSearch(
                artist: item,
                query: "unrelated track title",
                derivedTags: [tag]
            )
        )
    }

    @Test("Artist layout keeps cards fixed while supported widths add columns")
    func layoutMetrics() {
        let minimum = ArtistsLayoutMetrics(totalWidth: 1005)
        let standard = ArtistsLayoutMetrics(totalWidth: 1440)
        let wide = ArtistsLayoutMetrics(totalWidth: 1900)

        #expect(minimum.columnCount == 4)
        #expect(standard.columnCount == 6)
        #expect(wide.columnCount > standard.columnCount)
        #expect(minimum.tileWidth == 196)
        #expect(standard.tileWidth == 196)
        #expect(wide.tileWidth == 196)

        #expect(ArtistDetailLayoutMetrics(totalWidth: 1005).artworkSize == 180)
        #expect(ArtistDetailLayoutMetrics(totalWidth: 1440).artworkSize == 220)

        let columns = ArtistTrackTableColumnWidths(totalWidth: 900)
        #expect(columns.title >= 188)
        #expect(columns.album >= 172)
        #expect(abs(columns.total - 900) < 0.001)
    }
}

private extension ArtistsListeningDomainTests {
    func release(
        title: String,
        artistID: UUID,
        year: Int,
        kind: ReleaseKind
    ) -> LibraryAlbumProjection {
        LibraryAlbumProjection(
            id: UUID(),
            title: title,
            artistID: artistID,
            artist: "Artist",
            year: year,
            trackCount: 1,
            totalDuration: 180,
            isFavorite: false,
            favoriteDate: nil,
            customArtworkID: nil,
            releaseKind: kind
        )
    }
}

private extension ArtistsListeningDomainTests {
    func sortedIDs(
        _ artists: [ArtistPreview],
        descriptor: ArtistSortDescriptor,
        recentDates: [ArtistPreview.ID: Date]
    ) -> [ArtistPreview.ID] {
        ArtistListeningProjection.sortedArtists(
            artists,
            by: descriptor,
            recentDates: recentDates
        )
        .map(\.id)
    }

    func artist(
        id: String,
        name: String,
        albums: Int = 1,
        tracks: Int = 1
    ) -> ArtistPreview {
        ArtistPreview(
            id: id,
            name: name,
            albumCount: albums,
            trackCount: tracks
        )
    }

    func track(
        id: Int,
        album: String = "Album",
        year: Int = 2026,
        disc: Int = 1,
        number: Int = 1,
        lastPlayed: Date? = nil,
        palette: ArtworkPalette = .silver
    ) -> TrackPreview {
        TrackPreview(
            id: id,
            title: "Track \(id)",
            artist: "Artist",
            album: album,
            discNumber: disc,
            trackNumber: number,
            year: year,
            format: "FLAC",
            bitDepth: 24,
            sampleRate: 96,
            duration: 240,
            fileSize: "80 MB",
            lastPlayed: lastPlayed,
            rating: 5,
            isFavorite: false,
            artworkPalette: palette
        )
    }

    func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
