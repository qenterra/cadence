import AppKit
@testable import Cadence
import Foundation
import Testing

struct SecondAuditPresentationTests {
    @Test("Home removes content already represented by a higher-priority shelf")
    func homeCrossShelfDeduplication() {
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
        #expect(SettingsLayoutMetrics.maximumContentWidth == 640)
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
}
