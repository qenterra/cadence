import SwiftUI

struct AlbumsView: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        ProductionAlbumsView(
            model: model,
            store: model.librarySession.store
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.contentBackground)
    }
}
