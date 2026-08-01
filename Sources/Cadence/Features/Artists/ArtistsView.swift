import SwiftUI

struct ArtistsView: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        ProductionArtistsView(
            model: model,
            store: model.librarySession.store
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.contentBackground)
    }
}
