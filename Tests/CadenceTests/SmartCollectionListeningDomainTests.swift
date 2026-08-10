@testable import Cadence
import Foundation
import Testing

struct SmartCollectionListeningDomainTests {
    @Test("Canonical order is the default and remains stable")
    func canonicalOrder() {
        let tracks = [
            track(id: 30, title: "Third"),
            track(id: 10, title: "First"),
            track(id: 20, title: "Second"),
        ]

        let result = SmartCollectionListeningProjection.sortedTracks(
            tracks,
            by: .canonical
        )

        #expect(result.map(\.id) == [30, 10, 20])
    }

    @Test("Text sorts ignore case and diacritics with canonical tie breakers")
    func textSorting() {
        let tracks = [
            track(id: 4, title: "Élan", artist: "Beyoncé"),
            track(id: 3, title: "elan", artist: "beyonce"),
            track(id: 2, title: "Alpha", artist: "Mara"),
        ]

        let ascending = SmartCollectionListeningProjection.sortedTracks(
            tracks,
            by: SmartCollectionSortDescriptor(
                field: .title,
                direction: .ascending
            )
        )
        let descending = SmartCollectionListeningProjection.sortedTracks(
            tracks,
            by: SmartCollectionSortDescriptor(
                field: .artist,
                direction: .descending
            )
        )

        #expect(ascending.map(\.id) == [2, 4, 3])
        #expect(descending.map(\.id) == [2, 4, 3])
    }

    @Test("Album, format, year, and duration use their native values")
    func metadataSorting() {
        let tracks = [
            track(id: 1, album: "Zulu", year: 2026, format: "FLAC", duration: 310),
            track(id: 2, album: "Alpha", year: 2024, format: "WAV", duration: 180),
            track(id: 3, album: "Mono", year: 2025, format: "ALAC", duration: 240),
        ]

        #expect(sortedIDs(tracks, field: .album) == [2, 3, 1])
        #expect(sortedIDs(tracks, field: .format) == [3, 1, 2])
        #expect(sortedIDs(tracks, field: .year) == [2, 3, 1])
        #expect(sortedIDs(tracks, field: .duration, direction: .descending) == [1, 3, 2])
    }

    @Test("Activating a field toggles direction and number restores canonical")
    func descriptorActivation() {
        var descriptor = SmartCollectionSortDescriptor.canonical

        descriptor.activate(.title)
        #expect(descriptor == SmartCollectionSortDescriptor(field: .title, direction: .ascending))

        descriptor.activate(.title)
        #expect(descriptor == SmartCollectionSortDescriptor(field: .title, direction: .descending))

        descriptor.activate(.canonical)
        #expect(descriptor == .canonical)
    }

    @Test("Artwork layouts use the first four unique canonical albums")
    func artworkLayouts() {
        let tracks = [
            track(id: 1, album: "A", palette: .amberNoir),
            track(id: 2, album: "A", palette: .amberNoir),
            track(id: 3, album: "B", palette: .arctic),
            track(id: 4, album: "C", palette: .blueHour),
            track(id: 5, album: "D", palette: .forest),
            track(id: 6, album: "E", palette: .lilac),
        ]

        #expect(SmartCollectionListeningProjection.artworkLayout(for: []).slots.isEmpty)
        #expect(
            SmartCollectionListeningProjection.artworkLayout(
                for: Array(tracks.prefix(2))
            ).kind == .single
        )
        #expect(
            SmartCollectionListeningProjection.artworkLayout(
                for: Array(tracks.prefix(3))
            ).kind == .split
        )
        #expect(
            SmartCollectionListeningProjection.artworkLayout(
                for: Array(tracks.prefix(4))
            ).kind == .trio
        )

        let grid = SmartCollectionListeningProjection.artworkLayout(for: tracks)
        #expect(grid.kind == .grid)
        #expect(grid.slots.map(\.albumTitle) == ["A", "B", "C", "D"])
        #expect(grid.slots.map(\.palette) == [.amberNoir, .arctic, .blueHour, .forest])
    }

    @Test("Artwork and duration derive from canonical tracks, not visible sorting")
    func stableArtworkAndDuration() {
        let tracks = [
            track(id: 1, title: "Zulu", album: "First", duration: 90),
            track(id: 2, title: "Alpha", album: "Second", duration: 150),
        ]
        let sorted = SmartCollectionListeningProjection.sortedTracks(
            tracks,
            by: SmartCollectionSortDescriptor(
                field: .title,
                direction: .ascending
            )
        )

        #expect(sorted.map(\.id) == [2, 1])
        #expect(
            SmartCollectionListeningProjection.artworkLayout(for: tracks)
                .slots.map(\.albumTitle) == ["First", "Second"]
        )
        #expect(SmartCollectionListeningProjection.totalDuration(of: tracks) == 240)
    }
}

private extension SmartCollectionListeningDomainTests {
    func sortedIDs(
        _ tracks: [TrackPreview],
        field: SmartCollectionSortField,
        direction: SmartCollectionSortDirection = .ascending
    ) -> [TrackPreview.ID] {
        SmartCollectionListeningProjection.sortedTracks(
            tracks,
            by: SmartCollectionSortDescriptor(
                field: field,
                direction: direction
            )
        )
        .map(\.id)
    }

    func track(
        id: Int,
        title: String = "Track",
        artist: String = "Artist",
        album: String = "Album",
        year: Int = 2026,
        format: String = "FLAC",
        duration: TimeInterval = 240,
        palette: ArtworkPalette = .silver
    ) -> TrackPreview {
        TrackPreview(
            id: id,
            title: title,
            artist: artist,
            album: album,
            discNumber: 1,
            trackNumber: id,
            year: year,
            format: format,
            bitDepth: 24,
            sampleRate: 96,
            duration: duration,
            fileSize: "120 MB",
            lastPlayed: nil,
            rating: 4,
            isFavorite: false,
            artworkPalette: palette
        )
    }
}
