@testable import Cadence
import Foundation
import QenTerraMediaComponents
import Testing

struct CadencePlayerAdapterTests {
    @Test("Player presentation preserves the live Cadence clock and transport state")
    func playerPresentationPreservesClockAndState() {
        let snapshot = CadencePlayerBarSnapshot(
            item: CadencePlayerItemSnapshot(
                id: UUID(),
                title: "Glass Houses",
                artist: "Nora Vale",
                isExternal: false
            ),
            isPlaying: true,
            isShuffleEnabled: true,
            repeatMode: .one,
            presentationTime: 121,
            duration: 242,
            volume: 0.75,
            isMuted: false,
            isQueuePresented: true,
            timeDisplayMode: .remaining,
            libraryTrackCount: 8
        )

        let result = CadencePlayerAdapters.playerBar(from: snapshot)

        #expect(result.presentation.title == "Glass Houses")
        #expect(result.presentation.subtitle == "Nora Vale")
        #expect(result.presentation.isPlaying)
        #expect(result.presentation.isShuffleEnabled)
        #expect(result.presentation.repeatMode == .one)
        #expect(result.presentation.progress.progress == 0.5)
        #expect(result.presentation.progress.leadingText == "−2:01")
        #expect(result.presentation.progress.trailingText == "4:02")
        #expect(result.presentation.isQueuePresented)
        #expect(
            result.presentation.showNowPlayingAccessibilityLabel
                == "Show Now Playing for Glass Houses by Nora Vale"
        )
        #expect(result.showsFavoriteAccessory)
        #expect(!result.showsExternalImportAction)
    }

    @Test("External items expose import without inventing favorite ownership")
    func externalItemActions() {
        let snapshot = CadencePlayerBarSnapshot(
            item: CadencePlayerItemSnapshot(
                id: UUID(),
                title: "Stream",
                artist: "Remote Artist",
                isExternal: true
            ),
            isPlaying: false,
            isShuffleEnabled: false,
            repeatMode: .off,
            presentationTime: 0,
            duration: 0,
            volume: 0,
            isMuted: true,
            isQueuePresented: false,
            timeDisplayMode: .elapsed,
            libraryTrackCount: 0
        )

        let result = CadencePlayerAdapters.playerBar(from: snapshot)

        #expect(result.showsExternalImportAction)
        #expect(!result.showsFavoriteAccessory)
        #expect(result.presentation.favorite == nil)
        #expect(result.presentation.progress.progress == 0)
    }

    @Test("Empty player copy remains a Cadence-owned product decision")
    func emptyPlayerCopy() {
        let emptyLibrary = CadencePlayerAdapters.playerBar(
            from: .empty(libraryTrackCount: 0)
        )
        let populatedLibrary = CadencePlayerAdapters.playerBar(
            from: .empty(libraryTrackCount: 3)
        )

        #expect(emptyLibrary.presentation.emptyTitle == "Open an audio file to listen")
        #expect(emptyLibrary.presentation.emptySymbolName == "waveform")
        #expect(populatedLibrary.presentation.emptyTitle == "Select a Track")
        #expect(populatedLibrary.presentation.emptySymbolName == "music.note")
    }

    @Test("A stale seek completion cannot clear a newer pending seek")
    func pendingSeekIgnoresStaleCompletion() {
        let trackID = UUID()
        var state = CadencePendingSeekState()
        let first = state.begin(progress: 0.25, itemID: trackID)
        let second = state.begin(progress: 0.75, itemID: trackID)

        state.complete(first)
        #expect(state.progress == 0.75)

        state.complete(second)
        #expect(state.progress == nil)
    }

    @Test("Changing item clears an in-flight local seek")
    func pendingSeekClearsForNewItem() {
        var state = CadencePendingSeekState()
        _ = state.begin(progress: 0.4, itemID: UUID())

        state.updateCurrentItem(UUID())

        #expect(state.progress == nil)
    }

    @Test("Queue mapping preserves stale drag and current playback state")
    func queueMapping() {
        let stale = CadencePlayerAdapters.queueRow(
            CadenceQueueRowSnapshot(
                id: UUID(),
                title: "Missing file",
                subtitle: "Unknown artist",
                durationText: nil,
                isAvailable: false
            ),
            isCurrent: false,
            isSelected: true,
            isDraggable: true,
            isPlaying: false
        )
        let current = CadencePlayerAdapters.queueRow(
            CadenceQueueRowSnapshot(
                id: UUID(),
                title: "Current",
                subtitle: "Artist",
                durationText: "3:02",
                isAvailable: true
            ),
            isCurrent: true,
            isSelected: false,
            isDraggable: false,
            isPlaying: true
        )

        #expect(!stale.isAvailable)
        #expect(stale.isDraggable)
        #expect(stale.accessibilityValue == "Selected, unavailable")
        #expect(current.trailingSymbolName == nil)
        #expect(current.trailingAccessibilityLabel == "Playing")
    }

    @Test("Lyrics keep blank stanzas and blur synchronized inactive lines only")
    func lyricMapping() {
        let activeID = UUID()
        let presentations = CadencePlayerAdapters.lyricLines(
            [
                LyricLine(id: activeID, text: "Active", startTime: 1),
                LyricLine(id: UUID(), text: "Inactive", startTime: 2),
                LyricLine(id: UUID(), text: "Untimed", startTime: nil),
                LyricLine(id: UUID(), text: "   ", startTime: nil),
            ],
            activeLineID: activeID
        )

        #expect(presentations[0].blurRadius == 0)
        #expect(presentations[1].blurRadius == 0.45)
        #expect(presentations[2].blurRadius == 0)
        #expect(presentations[3].isBlankStanza)
    }

    @Test("Audio details retain Cadence order with stable public identifiers")
    func audioDetailsMapping() {
        let details = CadencePlayerAdapters.audioDetails(
            [
                AudioQualityDetail(label: "Format", value: "FLAC"),
                AudioQualityDetail(label: "Output", value: "Studio Display"),
            ]
        )

        #expect(details.map(\.id) == ["format", "output"])
        #expect(details.map(\.order) == [0, 1])
        #expect(details.map(\.value) == ["FLAC", "Studio Display"])
    }
}
