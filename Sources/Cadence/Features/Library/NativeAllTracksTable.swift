import SwiftUI

struct NativeAllTracksTable: View {
    @Bindable var model: CadenceAppModel
    @Bindable var window: LibraryTrackWindow
    let repositorySortAction: (LibraryTrackSort) async -> Void
    let refreshAction: CadenceRefreshAction
    @Binding var selection: Set<UUID>

    var body: some View {
        ProductionTrackTable(
            model: model,
            tracks: [],
            contentVersion: nil,
            queueSource: .allTracks,
            virtualWindow: window,
            repositorySortAction: repositorySortAction,
            selection: $selection,
            refreshAction: refreshAction
        )
    }
}
