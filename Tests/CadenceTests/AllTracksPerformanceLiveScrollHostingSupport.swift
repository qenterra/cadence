import AppKit
@testable import Cadence
import Foundation
import SwiftUI

enum RealWindowScrollProfile: CaseIterable {
    case sequentialRows
    case viewportJumps

    var label: String {
        switch self {
        case .sequentialRows: "sequential-row"
        case .viewportJumps: "viewport-jump"
        }
    }

    var sampleCount: Int {
        switch self {
        case .sequentialRows: 64
        case .viewportJumps: 32
        }
    }

    var warmupRow: Int {
        switch self {
        case .sequentialRows: 1000
        case .viewportJumps: 5000
        }
    }

    var productionWatchdogMilliseconds: Double? {
        switch self {
        case .sequentialRows: 1000 / 60
        case .viewportJumps: nil
        }
    }

    func targetRow(visibleRows: NSRange, rowCount: Int) -> Int {
        let visibleCount = max(visibleRows.length, 1)
        let lastVisibleRow = visibleRows.location + visibleCount - 1
        let advance = switch self {
        case .sequentialRows: 1
        case .viewportJumps: visibleCount
        }
        return min(lastVisibleRow + advance, rowCount - 1)
    }
}

struct RealWindowScrollTimingReport {
    let profile: RealWindowScrollProfile
    let durations: [Double]
    let newConfigurations: Int
    let newRoots: Int
    let identityChanges: Int

    var p50Milliseconds: Double {
        percentile(0.50)
    }

    var p95Milliseconds: Double {
        percentile(0.95)
    }

    var maximumMilliseconds: Double {
        durations.max() ?? 0
    }

    var millisecondsPerConfiguration: Double {
        durations.reduce(0, +) / Double(max(newConfigurations, 1))
    }

    func diagnostic(mode: String) -> String {
        String(
            format: "native-scroll mode=%@ profile=%@ samples=%d "
                + "p50=%.3fms p95=%.3fms max=%.3fms "
                + "configs=%d roots=%d identityChanges=%d ms/config=%.3f",
            mode,
            profile.label,
            durations.count,
            p50Milliseconds,
            p95Milliseconds,
            maximumMilliseconds,
            newConfigurations,
            newRoots,
            identityChanges,
            millisecondsPerConfiguration
        )
    }

    private func percentile(_ quantile: Double) -> Double {
        let sorted = durations.sorted()
        guard !sorted.isEmpty else {
            return 0
        }
        let rank = Int(ceil(Double(sorted.count) * quantile)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}

@MainActor
final class BenchmarkTrackHostingCell: NSTableCellView {
    let hostState = TrackTableRowHostState()
    private let probe: TrackTableWorkProbe
    private let hostingView: NSHostingView<BenchmarkTrackHostedRoot>

    init(
        contentMode: BenchmarkTrackRowContentMode,
        actionMenuMaterializationPolicy:
        TrackRowActionMenuMaterializationPolicy,
        probe: TrackTableWorkProbe
    ) {
        self.probe = probe
        hostingView = NSHostingView(
            rootView: BenchmarkTrackHostedRoot(
                state: hostState,
                contentMode: contentMode,
                actionMenuMaterializationPolicy:
                actionMenuMaterializationPolicy
            )
        )
        hostingView.sizingOptions = []
        super.init(frame: .zero)
        probe.recordHostingRootInstall()
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
        probe.recordHostConfiguration()
        if case let .track(configuration) = content,
           let previousTrackID = hostState.trackID,
           previousTrackID != configuration.track.id {
            probe.recordHostTrackIdentityChange()
        }
        hostState.content = content
    }
}

private struct BenchmarkTrackHostedRoot: View {
    @Bindable var state: TrackTableRowHostState
    let contentMode: BenchmarkTrackRowContentMode
    let actionMenuMaterializationPolicy:
        TrackRowActionMenuMaterializationPolicy

    var body: some View {
        switch state.content {
        case .placeholder:
            TrackTablePlaceholderRow()
        case let .track(configuration):
            switch contentMode {
            case .simpleHost:
                Text(configuration.track.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 58)
            case .fullStableIdentity:
                productionRow(configuration)
            case .fullResetIdentity:
                productionRow(configuration)
                    .id(configuration.track.id)
            }
        }
    }

    private func productionRow(
        _ configuration: TrackTableRowConfiguration
    ) -> ProductionTrackTableRow {
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
            workProbe: configuration.workProbe,
            actionMenuMaterializationPolicy:
            actionMenuMaterializationPolicy
        )
    }
}
