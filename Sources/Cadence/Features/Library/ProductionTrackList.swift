import SwiftUI

struct ProductionTrackList: View {
    @Bindable var model: CadenceAppModel
    let tracks: [LibraryTrackProjection]

    var body: some View {
        ProductionTrackTable(
            model: model,
            tracks: tracks
        )
    }
}
