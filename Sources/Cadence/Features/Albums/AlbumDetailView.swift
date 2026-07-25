import SwiftUI

struct AlbumDetailView: View {
    @Bindable var model: CadenceAppModel

    let album: AlbumPreview

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button {
                        model.requestAlbumsBack()
                    } label: {
                        Label(
                            "Back to \(model.albumsBackTitle)",
                            systemImage: "chevron.left"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.leftArrow, modifiers: .command)

                    AlbumListeningHeader(model: model, album: album)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .frame(maxHeight: 310)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            AlbumTrackTable(model: model, album: album)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
