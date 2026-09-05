import SwiftUI

enum TrackListScrollOwnership: Equatable, Sendable {
    case contained
    case page
}

enum TrackListLayout {
    static func contentHeight(
        rowCount: Int,
        showsHeader: Bool,
        density: TrackTableDensity = .standard
    ) -> CGFloat {
        CGFloat(max(rowCount, 0)) * density.rowHeight
            + (showsHeader ? density.headerHeight : 0)
    }
}

struct ProductionTrackList: View {
    @AppStorage(CadencePreferences.Keys.trackTableDensity)
    private var densityRawValue = TrackTableDensity.standard.rawValue
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
                    showsHeader: showsHeader,
                    density: density
                )
            )
        } else {
            table
        }
    }

    private var density: TrackTableDensity {
        TrackTableDensity(rawValue: densityRawValue) ?? .standard
    }
}
