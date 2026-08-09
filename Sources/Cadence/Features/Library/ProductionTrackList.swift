import SwiftUI

struct ProductionTrackList: View {
    @Bindable var model: CadenceAppModel
    let tracks: [LibraryTrackProjection]
    var context: TrackTableContext = .library
    var defaultSortDescriptor: TrackTableSortDescriptor?

    var body: some View {
        ProductionTrackTable(
            model: model,
            tracks: tracks,
            context: context,
            defaultSortDescriptor: defaultSortDescriptor
        )
    }
}
