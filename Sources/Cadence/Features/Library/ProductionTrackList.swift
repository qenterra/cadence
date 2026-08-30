import SwiftUI

enum TrackListScrollOwnership: Equatable, Sendable {
    case contained
    case page
}

enum TrackListLayout {
    static let rowHeight: CGFloat = 58
    static let headerHeight: CGFloat = 38

    static func contentHeight(
        rowCount: Int,
        showsHeader: Bool
    ) -> CGFloat {
        CGFloat(max(rowCount, 0)) * rowHeight
            + (showsHeader ? headerHeight : 0)
    }
}

struct ProductionTrackList: View {
    @Bindable var model: CadenceAppModel
    let tracks: [LibraryTrackProjection]
    let contentVersion: TrackTableContentVersion?
    var context: TrackTableContext = .library
    var showsHeader = true
    var compact = false
    var playlistID: UUID?
    var queueSource: PlaybackQueueSource?
    var reorderAction: (([UUID]) -> Void)?
    var onReachEnd: (() async -> Void)?
    var virtualWindow: LibraryTrackWindow?
    var repositorySortAction: ((LibraryTrackSort) async -> Void)?
    var selection: Binding<Set<UUID>>?
    var defaultSortDescriptor: TrackTableSortDescriptor?
    var refreshAction: CadenceRefreshAction?
    var scrollOwnership = TrackListScrollOwnership.contained

    var body: some View {
        let table = ProductionTrackTable(
            model: model,
            tracks: tracks,
            contentVersion: contentVersion,
            context: context,
            showsHeader: showsHeader,
            compact: compact,
            playlistID: playlistID,
            queueSource: queueSource,
            reorderAction: reorderAction,
            onReachEnd: onReachEnd,
            virtualWindow: virtualWindow,
            repositorySortAction: repositorySortAction,
            selection: selection,
            defaultSortDescriptor: defaultSortDescriptor,
            refreshAction: refreshAction,
            scrollOwnership: scrollOwnership
        )

        if scrollOwnership == .page {
            table.frame(
                height: TrackListLayout.contentHeight(
                    rowCount: virtualWindow?.totalCount ?? tracks.count,
                    showsHeader: showsHeader
                )
            )
        } else {
            table
        }
    }
}
