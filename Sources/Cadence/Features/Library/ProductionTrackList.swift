import SwiftUI

struct ProductionTrackList: View {
    @Bindable var model: CadenceAppModel
    let tracks: [LibraryTrackProjection]
    let contentVersion: TrackTableContentVersion
    var context: TrackTableContext = .library
    var defaultSortDescriptor: TrackTableSortDescriptor?
    var refreshAction: CadenceRefreshAction?

    var body: some View {
        ProductionTrackTable(
            model: model,
            tracks: tracks,
            contentVersion: contentVersion,
            context: context,
            defaultSortDescriptor: defaultSortDescriptor,
            refreshAction: refreshAction
        )
    }
}
