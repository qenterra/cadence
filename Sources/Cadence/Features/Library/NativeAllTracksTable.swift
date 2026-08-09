import SwiftUI

struct NativeAllTracksTable: View {
    @Bindable var model: CadenceAppModel
    @Bindable var window: LibraryTrackWindow
    let repositorySortAction: (LibraryTrackSort) async -> Void
    @Binding var selection: Set<UUID>

    var body: some View {
        ProductionTrackTable(
            model: model,
            tracks: [],
            queueSource: .allTracks,
            virtualWindow: window,
            repositorySortAction: repositorySortAction,
            selection: $selection
        )
    }
}
