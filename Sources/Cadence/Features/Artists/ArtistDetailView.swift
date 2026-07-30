import SwiftUI

struct ArtistDetailView: View {
    @Bindable var model: CadenceAppModel

    let artist: ArtistPreview

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width - 56, 760)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    Button {
                        model.requestArtistsBack()
                    } label: {
                        Label(
                            "Back to \(backTitle)",
                            systemImage: "chevron.left"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.leftArrow, modifiers: .command)

                    ArtistListeningHeader(
                        model: model,
                        artist: artist,
                        totalWidth: contentWidth
                    )

                    sectionSeparator

                    ArtistMostPlayed(
                        model: model,
                        artist: artist
                    )

                    sectionSeparator

                    ArtistAlbumsSection(
                        model: model,
                        artist: artist,
                        totalWidth: contentWidth
                    )

                    sectionSeparator

                    ArtistTrackTable(
                        model: model,
                        artist: artist,
                        totalWidth: contentWidth
                    )
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
        }
    }

    private var sectionSeparator: some View {
        Rectangle()
            .fill(CadenceTheme.separator)
            .frame(height: 1)
    }

    private var backTitle: String {
        model.hasContextualBackNavigation
            ? model.contextualBackTitle
            : model.artistsBackTitle
    }
}
