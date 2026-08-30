import AppKit
@testable import Cadence
import Foundation
import Testing

struct LibraryUXInfrastructureTests {
    @Test("Destination loading replaces only an empty data region")
    func destinationPresentation() {
        #expect(
            DestinationPresentation.resolve(
                hasResidentContent: false,
                isLoading: true
            ) == .loading
        )
        #expect(
            DestinationPresentation.resolve(
                hasResidentContent: true,
                isLoading: true
            ) == .content
        )
        #expect(
            DestinationPresentation.resolve(
                hasResidentContent: false,
                isLoading: false
            ) == .content
        )
    }

    @Test("Smart Collections mounts while its page-owned task is loading")
    func smartCollectionsDoesNotDeadlockRootPresentation() {
        #expect(
            DestinationPresentation.resolve(
                destination: .smartCollections,
                hasResidentContent: false,
                isLoading: true
            ) == .content
        )
    }

    @Test("Every scrollable library destination maps to a refresh scope")
    func destinationRefreshScopes() {
        #expect(NavigationDestination.home.refreshScope == .home)
        #expect(NavigationDestination.library.refreshScope == .library)
        #expect(NavigationDestination.allTracks.refreshScope == .allTracks)
        #expect(NavigationDestination.albums.refreshScope == .albums)
        #expect(NavigationDestination.artists.refreshScope == .artists)
        #expect(NavigationDestination.favorites.refreshScope == .favorites)
        #expect(NavigationDestination.playlists.refreshScope == .playlists)
        #expect(NavigationDestination.tags.refreshScope == .tags)
        #expect(NavigationDestination.smartCollections.refreshScope == .smartCollections)
        #expect(NavigationDestination.trash.refreshScope == .trash)
        #expect(NavigationDestination.importMusic.refreshScope == nil)
    }

    @Test("Escape cancels focused text entry before contextual navigation")
    func textEntryEscapePolicy() {
        #expect(
            TextEntryEscapePolicy.resolve(
                isFocused: true,
                textIsEmpty: false
            ) == .cancelEntry
        )
        #expect(
            TextEntryEscapePolicy.resolve(
                isFocused: true,
                textIsEmpty: true
            ) == .cancelEntry
        )
        #expect(
            TextEntryEscapePolicy.resolve(
                isFocused: false,
                textIsEmpty: true
            ) == .propagate
        )
    }

    @Test("Appearance changes do not recreate the root or Settings trees")
    func appearanceChangesPreserveViewIdentity() throws {
        let projectRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rootSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/Cadence/Features/Shell/CadenceRootView.swift"
            ),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/Cadence/CadenceApp.swift"
            ),
            encoding: .utf8
        )

        #expect(!rootSource.contains(".id(appearanceIdentity)"))
        #expect(
            !appSource.contains(
                ".id(AppearanceRefreshIdentity(rawValue: appearanceRawValue))"
            )
        )
    }

    @Test("Native track tables refresh only after a deliberate top pull")
    func nativeTrackTablePullRefreshPolicy() {
        #expect(TrackTablePullRefreshPolicy.progress(for: -12) == 0)
        #expect(TrackTablePullRefreshPolicy.progress(for: 0) == 0)
        #expect(TrackTablePullRefreshPolicy.progress(for: 36) == 0.5)
        #expect(TrackTablePullRefreshPolicy.progress(for: 90) == 1)
        #expect(!TrackTablePullRefreshPolicy.shouldRefresh(maximumPull: 71))
        #expect(TrackTablePullRefreshPolicy.shouldRefresh(maximumPull: 72))
    }

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

    @Test("Shared row buttons use static symbols and immediate press opacity")
    func sharedButtonSymbolsAreStatic() {
        #expect(
            CadenceRowButtonPressPresentation.opacity(isPressed: false) == 1
        )
        #expect(
            CadenceRowButtonPressPresentation.opacity(isPressed: true) == 0.72
        )
        #expect(HomeMediaTileAccessory.symbol(for: .track) == nil)
        #expect(
            HomeMediaTileAccessory.symbol(for: .album) == "chevron.right"
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

    @Test("Home pin projections remain separated by media kind")
    func homePinsAreGroupedByKind() {
        let sections = HomePinnedSectionKind.visibleKinds(
            albumCount: 1,
            artistCount: 2,
            playlistCount: 1,
            smartCollectionCount: 0
        )

        #expect(sections == [.albums, .artists, .playlists])
        #expect(
            sections.map(\.title)
                == ["Pinned Albums", "Pinned Artists", "Pinned Playlists"]
        )
    }

    @Test("Named playlist request captures selection without creating early")
    @MainActor
    func pendingPlaylistCreationCapturesSelection() {
        let ids = [UUID(), UUID()]
        let model = CadenceAppModel.testFixture()

        model.requestPlaylistCreation(adding: ids)

        #expect(model.pendingPlaylistCreation?.trackIDs == ids)
        #expect(model.pendingPlaylistCreation?.name.isEmpty == true)
        model.cancelPlaylistCreation()
        #expect(model.pendingPlaylistCreation == nil)
    }

    @Test("Failed playlist creation preserves the entered request")
    @MainActor
    func failedPlaylistCreationPreservesRequest() async {
        let model = CadenceAppModel.testFixture()
        model.requestPlaylistCreation(adding: [UUID()])
        model.updatePendingPlaylistName("Night Drive")

        await model.confirmPlaylistCreation()

        #expect(model.pendingPlaylistCreation?.name == "Night Drive")
        #expect(model.pendingPlaylistCreation?.trackIDs.count == 1)
    }

    @Test("Home recent items keep the playing track at the front")
    func homeRecentListeningSelection() {
        struct Item: Identifiable, Equatable {
            let id: Int
        }
        let items = (1 ... 10).map(Item.init)

        #expect(
            HomeListeningSelection.recentItems(
                items,
                limit: 6
            ).map(\.id) == Array(1 ... 6)
        )
        #expect(
            HomeListeningSelection.recentItems(
                items,
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
}

extension LibraryUXInfrastructureTests {
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

    @Test("Track rows keep format and synchronized lyrics out of list chrome")
    func trackRowsOmitTechnicalPills() throws {
        let projectRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/Cadence/Features/Library/ProductionTrackTableRowSupport.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains("formatPillTitle"))
        #expect(!source.contains("Text(\"LRC\")"))
    }

    @Test("Favorites type selection is a direct segmented control")
    func favoritesTypePickerIsDirect() throws {
        let projectRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/Cadence/Features/Library/LibraryFavoritesView.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains("Menu(\"Type\")"))
        #expect(source.contains(".pickerStyle(.segmented)"))
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

extension LibraryUXInfrastructureTests {
    @Test("Persistent Settings booleans use native switches")
    func settingsBooleanStyle() {
        #expect(
            SettingsBooleanControlPresentation.style
                == .nativeSwitch
        )
        #expect(
            SettingsBooleanControlPresentation.size
                == .small
        )
        #expect(
            SettingsBooleanControlPresentation.alignment
                == .trailing
        )
    }

    @Test("Navigation Settings uses checkboxes and lets Home move")
    func settingsNavigationControls() throws {
        let projectRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/Cadence/Features/Settings/SettingsSidebarCard.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains(".toggleStyle(.checkbox)"))
        #expect(!source.contains("source != .home"))
        #expect(!source.contains("destination != .home"))
    }

    @Test("About presents a compact product hero and one resource list")
    func settingsAboutContent() {
        #expect(SettingsAboutContent.resourceTitles == [
            "GitHub Profile",
            "Source Code",
            "Wiki",
            "MIT License",
            "Third-Party Notices",
        ])
        #expect(SettingsAboutContent.usesProductHero)
    }

    @Test("Action semantics map confirmation to blue and deletion to red")
    func semanticActionColors() {
        #expect(
            CadenceActionTone.confirmation.semanticColor
                == .systemBlue
        )
        #expect(
            CadenceActionTone.destructive.semanticColor
                == .systemRed
        )
    }

    @Test("Catalog sort choices update directly without nested state")
    func catalogSortSelection() {
        var selection = CatalogSortSelection(
            field: AlbumSortField.artist,
            direction: .ascending
        )

        selection.select(field: .title)
        #expect(selection.field == .title)
        #expect(selection.direction == .ascending)

        selection.select(direction: .descending)
        #expect(selection.field == .title)
        #expect(selection.direction == .descending)
    }
}
