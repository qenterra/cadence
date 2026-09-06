import QenTerraComponents
import SwiftUI

struct EmptyLibraryView: View {
    let title: String
    let description: String
    let importAction: () -> Void

    var body: some View {
        ContentStateView(
            state: .empty(title: title, message: description),
            symbolName: "music.note",
            actions: [
                PresentationAction(
                    title: "Import Music",
                    style: .primary,
                    handler: importAction
                )
            ],
            presentation: .nativeUnavailable
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
