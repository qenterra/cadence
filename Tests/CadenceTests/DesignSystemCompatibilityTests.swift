import AppKit
@testable import Cadence
import QenTerraComponents
import QenTerraDesignTokens
import QenTerraMediaComponents
import SwiftUI
import Testing

struct DesignSystemCompatibilityTests {
    @Test("Cadence constructs the shared value contracts used by its adapters")
    @MainActor
    func cadenceBuildsAgainstSharedValueContracts() {
        let configuration = DesignSystemConfiguration(
            appearance: .system,
            productProfile: .cadence,
            density: .standard
        )
        let rowState = InteractiveRowState()
        let about = CadenceAboutConfiguration.make(resources: [])
        let media = MediaItemPresentation(
            id: "track", title: "Track", subtitle: "Artist", metadata: "Album",
            isSelected: true, isCurrent: true, isPlaying: false, isAvailable: true
        )
        let lyric = LyricLinePresentation(
            id: "line", text: "Words", isActive: true, isSynchronized: true
        )
        let table = MediaTableRowPresentation(
            id: "track", title: "Track", creator: "Artist", collection: "Album",
            year: "2026", duration: "3:42", isExplicit: false, isFavorite: true,
            isCurrent: true, isPlaying: false, isAvailable: true, artworkIdentity: nil
        )
        let palette = ArtworkAccentPalette(colors: [])
        let tint = ArtworkAccentGradientTint(
            color: ArtworkAccentColor(red: 0.2, green: 0.3, blue: 0.4), amount: 0.25
        )

        #expect(configuration.productProfile == .cadence)
        #expect(!rowState.isSelected)
        #expect(about.applicationName == "Cadence")
        #expect(media.id == "track")
        #expect(lyric.text == "Words")
        #expect(table.creator == "Artist")
        #expect(palette.colors.isEmpty)
        #expect(tint.amount == 0.25)

        _ = CadenceTrackTableAdapter.makePlaybackIndicator()
        _ = NativeMediaTableView(frame: .zero)
        _ = NativeMediaTableCell(frame: .zero)
        _ = ArtworkAccentGradientView(
            frame: .zero,
            device: nil
        )
    }

    @Test("Every shared visual family consumed by Cadence remains type-visible")
    func cadenceBuildsAgainstSharedVisualEntryPoints() {
        _ = PageHeader<EmptyView>.self
        _ = PageScrollView<EmptyView>.self
        _ = ResizableSplitView<EmptyView, EmptyView>.self
        _ = NavigationRail<String>.self
        _ = SortMenu<String>.self
        _ = ContentStateView.self
        _ = StatusBanner.self
        _ = DropZone.self
        _ = OperationStateView.self
        _ = AboutPage<EmptyView>.self
        _ = AboutResourceRow.self

        _ = ArtworkSurface<EmptyView>.self
        _ = QenTerraMediaComponents.ArtworkPlaceholder.self
        _ = ArtworkMosaic<EmptyView>.self
        _ = MediaTile<String, EmptyView, EmptyView>.self
        _ = MediaRow<String, EmptyView, EmptyView>.self
        _ = MediaGrid<EmptyView>.self
        _ = MediaShelf<EmptyView>.self
        _ = FavoriteControl.self

        _ = PlayerBarPresentation.self
        _ = PlayerBarActions.self
        _ = QenTerraMediaComponents.PlaybackProgressControl.self
        _ = QenTerraMediaComponents.AirPlayRoutePicker.self
        _ = PlaybackQueueRow<String, EmptyView, EmptyView, EmptyView, EmptyView>.self
        _ = QueueInsertionIndicator.self
        _ = QueueDragPreview<EmptyView>.self
        _ = LyricsViewport<String, String, EmptyView>.self
        _ = LyricsEdgeFade.self
        _ = LyricsEdgeFade(presentation: .viewportMask(.init(
            topOpaqueLocation: 0.18,
            bottomOpaqueLocation: 0.88
        )))
        _ = MediaMetadataBadge.self
        _ = AudioDetailsView.self
    }
}
