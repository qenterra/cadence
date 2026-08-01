import SwiftUI

struct TagsView: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        ProductionTagsView(
            model: model,
            store: model.librarySession.store
        )
        .background(CadenceTheme.contentBackground)
        .onExitCommand {
            if model.selectedProductionTagEditingTrackID != nil {
                model.selectedProductionTagEditingTrackID = nil
            }
        }
    }
}
