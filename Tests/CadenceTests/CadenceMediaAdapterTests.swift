@testable import Cadence
import Foundation
import QenTerraMediaComponents
import Testing

struct CadenceMediaAdapterTests {
    @Test("Every Cadence artwork palette maps to the shared ready-content palette")
    func artworkPaletteMapping() {
        let symbols: [Cadence.ArtworkPalette: String] = [
            .amberNoir: "waveform",
            .arctic: "snowflake",
            .blueHour: "moonphase.waning.crescent",
            .ember: "sparkles",
            .forest: "leaf",
            .lilac: "circle.hexagongrid",
            .ocean: "water.waves",
            .rose: "camera.macro",
            .silver: "circle.grid.cross",
            .sunset: "sun.horizon",
        ]

        for (palette, symbol) in symbols {
            #expect(palette.designSystemPalette.symbolName == symbol)
        }
    }

    @Test("Cadence placeholder vocabulary maps without leaking product names")
    func placeholderMapping() {
        #expect(ArtworkPlaceholder.artist.designSystemKind == .artist)
        #expect(ArtworkPlaceholder.album.designSystemKind == .album)
        #expect(ArtworkPlaceholder.track.designSystemKind == .track)
        #expect(ArtworkPlaceholder.playlist.designSystemKind == .playlist)
        #expect(ArtworkPlaceholder.smartCollection.designSystemKind == .collection)
        #expect(
            CadenceMediaAdapters.artworkState(for: .catalog(.silver)) == .content
        )
        #expect(
            CadenceMediaAdapters.artworkState(
                for: .custom(ArtworkAsset(data: Data()))
            ) == .content
        )
        #expect(
            CadenceMediaAdapters.artworkState(
                for: .placeholder(.smartCollection)
            ) == .placeholder(.collection)
        )
    }

    @Test("Every catalog size reaches the shared grid without normalization")
    func catalogGridMapping() {
        for size in CatalogCardSize.allCases {
            let range = CatalogCardLayoutMetrics.widthRange(for: size)
            let layout = MediaGridLayout.resolve(
                productProfile: .cadence,
                minimumWidth: range.lowerBound,
                maximumWidth: range.upperBound,
                spacing: 18,
                honorsExplicitSizing: true
            )

            #expect(layout.minimumWidth == range.lowerBound)
            #expect(layout.maximumWidth == range.upperBound)
            #expect(layout.spacing == 18)
        }
    }

    @Test("Track projections preserve product truth in the shared presentation")
    func trackProjectionMapping() throws {
        let track = try LibraryTrackProjection(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000016")),
            title: "  ",
            artistID: nil,
            artist: "Synthetic Artist",
            albumID: nil,
            album: "Synthetic Album",
            duration: 182,
            year: 2026,
            codec: "FLAC",
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            isFavorite: true,
            customArtworkID: nil,
            artworkID: nil,
            relativeMediaPath: "synthetic.flac",
            lastPlayedAt: nil,
            hasSynchronizedLyrics: false
        )
        let row = TrackRowDisplayProjection(
            track: track,
            isCurrentTrack: true,
            isPlaying: true
        )

        let item = CadenceMediaAdapters.mediaItem(
            row,
            isSelected: true,
            isAvailable: false
        )
        #expect(item.id == track.id)
        #expect(item.title == "Untitled Track")
        #expect(item.subtitle == "Synthetic Artist")
        #expect(item.metadata == "Synthetic Album · 3:02")
        #expect(item.isSelected)
        #expect(item.isCurrent)
        #expect(item.isPlaying)
        #expect(!item.isAvailable)
    }
}
