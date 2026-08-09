import SwiftUI

struct VirtualTrackTablePage: View {
    @Bindable var model: CadenceAppModel
    @Bindable var window: LibraryTrackWindow
    let page: Int
    let columns: [TrackTableColumn]
    let widths: TrackTableResolvedWidths
    let playlistID: UUID?
    let queueSource: PlaybackQueueSource?
    @Binding var selection: Set<UUID>
    let tableHasFocus: Bool
    let select: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rowRange, id: \.self) { index in
                if let track = window.track(at: index) {
                    ProductionTrackTableRow(
                        model: model,
                        track: track,
                        queue: [track],
                        columns: columns,
                        widths: widths,
                        playlistID: playlistID,
                        queueSource: queueSource,
                        reorderAction: nil,
                        actionTrackIDs: [track.id],
                        isSelected: selection.contains(track.id),
                        isFocused: tableHasFocus
                            && selection.contains(track.id),
                        select: {
                            select(track.id)
                        }
                    )
                } else {
                    TrackTableLoadingRow(widths: widths)
                }
            }
        }
        .task(id: page) {
            await window.load(page: page)
        }
    }

    private var rowRange: Range<Int> {
        let lowerBound = page * window.pageSize
        let upperBound = min(
            lowerBound + window.pageSize,
            window.totalCount
        )
        return lowerBound ..< upperBound
    }
}

private struct TrackTableLoadingRow: View {
    let widths: TrackTableResolvedWidths

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: CadenceTheme.radiusControl, style: .continuous)
                .fill(CadenceTheme.subduedFill)
                .frame(width: 40, height: 40)
            RoundedRectangle(cornerRadius: CadenceTheme.radiusControl, style: .continuous)
                .fill(CadenceTheme.subduedFill)
                .frame(
                    width: min(CGFloat(widths.song) * 0.55, 180),
                    height: 12
                )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .accessibilityLabel("Loading track")
    }
}
