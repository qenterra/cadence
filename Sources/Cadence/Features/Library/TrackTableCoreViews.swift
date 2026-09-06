import AppKit
import Observation
import QenTerraMediaComponents
import SwiftUI

typealias TrackTableView = NativeMediaTableView

@MainActor
@Observable
final class TrackTableInteractionState {
    private(set) var isLiveScrolling = false

    func beginLiveScroll() {
        isLiveScrolling = true
    }

    func endLiveScroll() {
        isLiveScrolling = false
    }
}

struct TrackTableRowConfiguration {
    let model: CadenceAppModel
    let track: LibraryTrackProjection
    let queueIDProvider: TrackTableQueueIDProvider
    let columns: [TrackTableColumn]
    let widths: TrackTableResolvedWidths
    let playlistID: UUID?
    let queueSource: PlaybackQueueSource?
    let reorderAction: (([UUID]) -> Void)?
    let resolveDraggedTrackIDs: (Set<UUID>) -> Set<UUID>
    let actionTrackIDs: [UUID]
    let isSelected: Bool
    let isFocused: Bool
    let artworkLoader: ProductionArtworkLoader?
    let artworkWorkProbe: ProductionArtworkWorkProbe?
    var interactionState: TrackTableInteractionState?
    var workProbe: TrackTableWorkProbe?
    let select: () -> Void
}

enum TrackTableHostedContent {
    case placeholder(row: Int)
    case track(TrackTableRowConfiguration)
}

@MainActor
@Observable
final class TrackTableRowHostState {
    var content: TrackTableHostedContent = .placeholder(row: -1)

    var trackID: UUID? {
        guard case let .track(configuration) = content else {
            return nil
        }
        return configuration.track.id
    }
}

struct TrackTableHostedRoot: View {
    @Bindable var state: TrackTableRowHostState

    var body: some View {
        switch state.content {
        case .placeholder:
            TrackTablePlaceholderRow()
        case let .track(configuration):
            ProductionTrackTableRow(
                model: configuration.model,
                track: configuration.track,
                queueIDProvider: configuration.queueIDProvider,
                columns: configuration.columns,
                widths: configuration.widths,
                playlistID: configuration.playlistID,
                queueSource: configuration.queueSource,
                reorderAction: configuration.reorderAction,
                resolveDraggedTrackIDs: configuration.resolveDraggedTrackIDs,
                actionTrackIDs: configuration.actionTrackIDs,
                isSelected: configuration.isSelected,
                isFocused: configuration.isFocused,
                artworkLoader: configuration.artworkLoader,
                artworkWorkProbe: configuration.artworkWorkProbe,
                select: configuration.select,
                interactionState: configuration.interactionState,
                workProbe: configuration.workProbe
            )
        }
    }
}

@MainActor
final class TrackTableHostingCell: NSTableCellView {
    private let probe: TrackTableWorkProbe?
    let hostState: TrackTableRowHostState
    private let hostingView: NSHostingView<TrackTableHostedRoot>

    init(
        frame frameRect: NSRect = .zero,
        probe: TrackTableWorkProbe? = nil
    ) {
        self.probe = probe
        let hostState = TrackTableRowHostState()
        self.hostState = hostState
        hostingView = NSHostingView(
            rootView: TrackTableHostedRoot(state: hostState)
        )
        hostingView.sizingOptions = []
        super.init(frame: frameRect)
        probe?.recordHostingRootInstall()
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func configure(_ content: TrackTableHostedContent) {
        probe?.recordHostConfiguration()
        if case let .track(configuration) = content,
           let previousTrackID = hostState.trackID,
           previousTrackID != configuration.track.id {
            probe?.recordHostTrackIdentityChange()
        }
        hostState.content = content
    }

    var hostingSizingOptions: NSHostingSizingOptions {
        hostingView.sizingOptions
    }
}

struct TrackTablePlaceholderRow: View {
    var body: some View {
        HStack(spacing: TrackTableColumnPolicy.songContentSpacing) {
            Color.clear
                .frame(width: TrackTableColumnPolicy.favoriteControlWidth)
            RoundedRectangle(
                cornerRadius: CadenceTheme.radiusControl,
                style: .continuous
            )
            .fill(CadenceTheme.subduedFill)
            .frame(width: 40, height: 40)
            RoundedRectangle(
                cornerRadius: CadenceTheme.radiusControl,
                style: .continuous
            )
            .fill(CadenceTheme.subduedFill)
            .frame(width: 180)
            .frame(height: 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TrackTableColumnPolicy.horizontalInset)
        .frame(height: 58)
        .redacted(reason: .placeholder)
    }
}
