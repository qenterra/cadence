import AppKit
@testable import Cadence
import Foundation
import Testing

struct SecondAuditPresentationTests {
    @Test("Home selection can exclude identities when a shelf requires it")
    func homeExplicitShelfDeduplication() {
        struct Item: Identifiable, Equatable {
            let id: Int
        }

        let items = (1 ... 6).map(Item.init)
        let result = HomeListeningSelection.items(
            items,
            excludingIDs: [1, 3, 5],
            limit: 3
        )

        #expect(result.map(\.id) == [2, 4, 6])
    }

    @MainActor
    @Test("Home renders one stored track in both listening shelves")
    func homeFavoriteAndRecentShelvesShareTrack() {
        let model = CadenceAppModel.testFixture()
        let store = model.librarySession.store
        let shared = LibraryTrackProjection(
            id: UUID(),
            title: "Shared Home Track",
            artistID: nil,
            artist: "Artist",
            albumID: nil,
            album: "Album",
            duration: 180,
            year: 2026,
            codec: "FLAC",
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            isFavorite: true,
            customArtworkID: nil,
            artworkID: nil,
            relativeMediaPath: "shared-home-track.flac",
            lastPlayedAt: Date(timeIntervalSince1970: 1_800_000_000),
            hasSynchronizedLyrics: false
        )
        store.favoriteTracks = [shared]
        store.recentlyPlayedTracks = [shared]
        let view = ProductionHomeView(model: model, store: store)

        #expect(reflectedTrackIDs(in: view.recentlyPlayed).contains(shared.id))
        #expect(reflectedTrackIDs(in: view.favorites).contains(shared.id))
    }

    @Test("Browse gives the track column an explicit idle, loading, and empty state")
    func browseTrackColumnStates() {
        #expect(
            LibraryBrowserColumnPresentation.resolve(
                hasSelection: false,
                loadState: .idle,
                itemCount: 0
            ) == .selectionRequired
        )
        #expect(
            LibraryBrowserColumnPresentation.resolve(
                hasSelection: true,
                loadState: .loading,
                itemCount: 0
            ) == .loading
        )
        #expect(
            LibraryBrowserColumnPresentation.resolve(
                hasSelection: true,
                loadState: .ready,
                itemCount: 0
            ) == .empty
        )
        #expect(
            LibraryBrowserColumnPresentation.resolve(
                hasSelection: true,
                loadState: .failed(LibraryStoreFailure(message: "Offline")),
                itemCount: 0
            ) == .failed("Offline")
        )
    }

    @Test("Now Playing names the secondary panel once with user-facing language")
    func nowPlayingPanelLabels() {
        #expect(NowPlayingPanel.lyrics.title == "Lyrics")
        #expect(NowPlayingPanel.queue.title == "Up Next")
        #expect(!NowPlayingPanelPresentation.showsRedundantHeaderTitle)
        #expect(!NowPlayingPanelPresentation.showsUpNextSectionTitle)
    }

    @Test("Import selection copy uses exact counts and production language")
    func importSelectionCopy() {
        #expect(
            ImportReviewCopy.selectionSummary(count: 1, size: "94 MB")
                == "1 track selected · 94 MB"
        )
        #expect(
            ImportReviewCopy.selectionSummary(count: 5, size: "458 MB")
                == "5 tracks selected · 458 MB"
        )
        #expect(ImportReviewCopy.importAction(count: 1) == "Import 1 Track")
        #expect(ImportReviewCopy.importAction(count: 5) == "Import 5 Tracks")
        #expect(
            !ImportMusicHeaderPresentation.showsPreviewControls(
                hasPreviewFixture: true,
                hidesPreviewChrome: true
            )
        )
    }

    @Test("Settings use compact native-scale spacing")
    func settingsDensity() {
        #expect(SettingsLayoutMetrics.sectionSpacing == CadenceLayout.contentGap)
        #expect(SettingsLayoutMetrics.cardInset == CadenceLayout.contentGap)
        #expect(SettingsLayoutMetrics.cardContentSpacing == CadenceLayout.controlGap)
        #expect(SettingsLayoutMetrics.maximumContentWidth == 680)
    }

    @Test("Sidebar settings expose one freely ordered destination list")
    func sidebarSettingsAreFlat() throws {
        let sidebarSource = try source(
            at: "Sources/Cadence/Features/Settings/SettingsSidebarCard.swift"
        )

        #expect(sidebarSource.contains("ForEach(orderedDestinations)"))
        #expect(!sidebarSource.contains("orderedSections"))
        #expect(!sidebarSource.contains("section.group.title"))
        #expect(!sidebarSource.contains("navigationGroup =="))
    }

    @Test("Settings tabs keep one stable strip and deterministic glass policy")
    func settingsTabGlassPresentation() {
        #expect(
            CadenceGlassSurfacePresentation.resolve(
                usesStableSystemControls: false,
                reduceTransparency: false
            ) == .nativeGlass
        )
        #expect(
            CadenceGlassSurfacePresentation.resolve(
                usesStableSystemControls: true,
                reduceTransparency: false
            ) == .opaqueFallback
        )
        #expect(
            CadenceGlassSurfacePresentation.resolve(
                usesStableSystemControls: false,
                reduceTransparency: true
            ) == .opaqueFallback
        )
        #expect(
            CadenceGlassSurfacePresentation.resolve(
                usesStableSystemControls: true,
                reduceTransparency: true
            ) == .opaqueFallback
        )

        #expect(SettingsTabStripMetrics.iconFrame == CGSize(width: 24, height: 22))
        #expect(SettingsTabStripMetrics.minimumTabSize == CGSize(width: 76, height: 54))
        #expect(SettingsTabStripMetrics.rowSpacing == CadenceLayout.compactGap)

        let baseline = SettingsTabStripMetrics.metrics(for: .general)
        for tab in CadenceSettingsTab.allCases {
            #expect(SettingsTabStripMetrics.metrics(for: tab) == baseline)
        }
    }

    @Test("Settings source keeps glass at the strip boundary")
    func settingsTabSourceContract() throws {
        let tabSource = try source(
            at: "Sources/Cadence/Features/Settings/SettingsTabStrip.swift"
        )
        let appSource = try source(at: "Sources/Cadence/CadenceApp.swift")
        let stripStart = try #require(
            appSource.range(of: "SettingsTabStrip(selection: $selection)")
        )
        let separator = try #require(
            appSource.range(
                of: "CadenceSeparator()",
                range: stripStart.lowerBound ..< appSource.endIndex
            )
        )
        let stripSource = String(
            appSource[
                stripStart.lowerBound ..< separator.upperBound
            ]
        )

        #expect(!tabSource.contains("GlassEffectContainer"))
        #expect(!tabSource.contains(".buttonStyle(.glass"))
        #expect(
            tabSource.components(separatedBy: ".buttonStyle(.plain)").count
                == 2
        )
        #expect(
            stripSource.components(
                separatedBy: ".cadenceGlassSurface("
            ).count == 2
        )

        var cursor = stripSource.startIndex
        for fragment in [
            "SettingsTabStrip(selection: $selection)",
            ".frame(maxWidth: .infinity)",
            ".padding(.horizontal, CadenceLayout.contentGap)",
            ".padding(.vertical, CadenceLayout.compactGap)",
            ".cadenceGlassSurface(",
            "CadenceSeparator()",
        ] {
            let match = try #require(
                stripSource.range(
                    of: fragment,
                    range: cursor ..< stripSource.endIndex
                )
            )
            cursor = match.upperBound
        }
    }

    @Test("Every settings card symbol resolves on the supported macOS baseline")
    func settingsSymbolsResolve() {
        let symbols = [
            "play.rectangle",
            "circle.lefthalf.filled",
            "externaldrive",
            "sidebar.left",
            "network",
            "keyboard",
            "arrow.triangle.2.circlepath",
            "person.2.circle",
            "chevron.left.forwardslash.chevron.right",
            "book.pages",
            "doc.text",
            "books.vertical",
            "cup.and.saucer",
            "music.note.house",
        ]

        for symbol in symbols {
            #expect(
                NSImage(
                    systemSymbolName: symbol,
                    accessibilityDescription: nil
                ) != nil,
                "Missing SF Symbol: \(symbol)"
            )
        }
    }

    private func source(at relativePath: String) throws -> String {
        let projectRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: projectRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}

private func reflectedTrackIDs(
    in value: Any,
    depth: Int = 0
) -> [UUID] {
    if let tracks = value as? [LibraryTrackProjection] {
        return tracks.map(\.id)
    }
    guard depth < 32 else {
        return []
    }
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle != .class else {
        return []
    }
    return mirror.children.flatMap {
        reflectedTrackIDs(in: $0.value, depth: depth + 1)
    }
}
