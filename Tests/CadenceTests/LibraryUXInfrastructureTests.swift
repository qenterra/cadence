import AppKit
@testable import Cadence
import Foundation
import Testing

struct LibraryUXInfrastructureTests {
    @Test("System appearance releases the explicit AppKit override")
    func appearanceOverrides() {
        #expect(CadenceAppearance.system.appKitAppearance == nil)
        #expect(CadenceAppearance.light.appKitAppearance?.name == .aqua)
        #expect(CadenceAppearance.dark.appKitAppearance?.name == .darkAqua)
    }

    @Test("Track table sorting toggles canonical text and numeric order")
    func trackTableSorting() {
        let tracks = [
            track(title: "Beta", year: 2024),
            track(title: "Alpha", year: 2026),
        ]

        #expect(
            TrackTableSortDescriptor(
                field: .song,
                direction: .ascending
            ).sorted(tracks).map(\.title) == ["Alpha", "Beta"]
        )
        #expect(
            TrackTableSortDescriptor(
                field: .year,
                direction: .descending
            ).sorted(tracks).map(\.year) == [2026, 2024]
        )
    }

    @Test("Home pin projection tolerates duplicate library and saved identifiers")
    func homePinsDeduplicateIdentifiers() {
        struct Item: Identifiable, Equatable {
            let id: UUID
            let title: String
        }

        let firstID = UUID()
        let secondID = UUID()
        let first = Item(id: firstID, title: "First")
        let duplicate = Item(id: firstID, title: "Duplicate")
        let second = Item(id: secondID, title: "Second")

        let ordered = HomePinStore.orderedItems(
            ids: [firstID, firstID, secondID],
            source: [first, duplicate, second]
        )

        #expect(ordered == [first, second])
    }

    @Test("Home recent items omit the track already visible in the player")
    func homeRecentListeningSelection() {
        struct Item: Identifiable, Equatable {
            let id: Int
        }
        let items = (1 ... 10).map(Item.init)

        #expect(
            HomeListeningSelection.recentItems(
                items,
                excludingID: 1,
                limit: 6
            ).map(\.id) == Array(2 ... 7)
        )
        #expect(
            HomeListeningSelection.recentItems(
                items,
                excludingID: nil,
                limit: 0
            ).isEmpty
        )
    }

    @Test("Home favorites preview shares six slots across media types")
    func homeFavoritesPreviewBudget() {
        #expect(
            HomeFavoritesPreviewBudget.resolve(
                trackCount: 8,
                albumCount: 2,
                artistCount: 1,
                limit: 6
            ) == HomeFavoritesPreviewBudget(
                trackLimit: 3,
                albumLimit: 2,
                artistLimit: 1
            )
        )
        #expect(
            HomeFavoritesPreviewBudget.resolve(
                trackCount: 0,
                albumCount: 5,
                artistCount: 1,
                limit: 6
            ) == HomeFavoritesPreviewBudget(
                trackLimit: 0,
                albumLimit: 5,
                artistLimit: 1
            )
        )
    }

    @Test("Track artwork waveform represents only the active playing track")
    @MainActor
    func trackArtworkPlaybackSymbol() {
        #expect(
            ProductionTrackTableRow.artworkOverlaySymbolName(
                isCurrentTrack: true,
                isPlaying: true
            ) == "waveform"
        )
        #expect(
            ProductionTrackTableRow.artworkOverlaySymbolName(
                isCurrentTrack: false,
                isPlaying: true
            ) == "play.fill"
        )
        #expect(
            ProductionTrackTableRow.artworkOverlaySymbolName(
                isCurrentTrack: true,
                isPlaying: false
            ) == "play.fill"
        )
    }

    @Test("Track format pills omit leading file-extension separators")
    @MainActor
    func trackFormatPillTitle() {
        #expect(
            ProductionTrackTableRow.formatPillTitle(".mp3") == "MP3"
        )
        #expect(
            ProductionTrackTableRow.formatPillTitle("flac") == "FLAC"
        )
        #expect(
            ProductionTrackTableRow.formatPillTitle(" ..aac") == "AAC"
        )
    }

    @Test("Production Smart Collections match inherited tag descendants")
    func productionSmartCollectionTags() {
        let genreID = UUID()
        let ambientID = UUID()
        let first = track(title: "Ambient")
        let second = track(title: "Untagged")
        let tags = [
            genreID: LibraryTagProjection(
                id: genreID,
                displayPath: "Genre",
                groupPath: nil
            ),
            ambientID: LibraryTagProjection(
                id: ambientID,
                displayPath: "Genre / Ambient",
                groupPath: "Genre"
            ),
        ]
        let root = SmartCollectionRuleGroup(
            combinator: .all,
            children: [
                .condition(
                    SmartCollectionRuleCondition(
                        field: .tag,
                        operator: .is,
                        value: .tag(
                            id: genreID.uuidString,
                            scope: .includeSubtags
                        )
                    )
                ),
            ]
        )

        let result = ProductionSmartCollectionEvaluator().evaluate(
            root: root,
            index: ProductionSmartCollectionIndex(
                tracks: [first, second],
                effectiveTagIDsByTrackID: [
                    first.id: [ambientID],
                ],
                tagsByID: tags
            )
        )

        #expect(result.map(\.id) == [first.id])
    }

    private func track(
        title: String,
        year: Int = 2026
    ) -> LibraryTrackProjection {
        LibraryTrackProjection(
            id: UUID(),
            title: title,
            artistID: nil,
            artist: "Artist",
            albumID: nil,
            album: "Album",
            duration: 180,
            year: year,
            codec: "flac",
            sampleRate: 44.1,
            channelCount: 2,
            bitDepth: 24,
            isFavorite: false,
            customArtworkID: nil,
            artworkID: nil,
            relativeMediaPath: "\(UUID()).flac",
            lastPlayedAt: nil,
            hasSynchronizedLyrics: false
        )
    }
}
