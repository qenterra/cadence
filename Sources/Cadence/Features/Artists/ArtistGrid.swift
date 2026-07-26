import SwiftUI

struct ArtistGrid: View {
    @Bindable var model: CadenceAppModel

    let title: String
    let subtitle: String
    let artists: [ArtistPreview]
    let origin: ArtistsBrowseOrigin
    let scrollScope: ArtistShelfKind?
    let showsSortMenu: Bool
    var backAction: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let metrics = ArtistsLayoutMetrics(totalWidth: geometry.size.width)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header

                    if artists.isEmpty {
                        ContentUnavailableView {
                            Label(emptyTitle, systemImage: "person.2")
                        } description: {
                            Text(emptyDescription)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    } else {
                        ArtistTileGrid(
                            model: model,
                            artists: artists,
                            metrics: metrics,
                            origin: origin
                        )
                    }
                }
                .padding(.horizontal, ArtistsLayoutMetrics.horizontalPadding)
                .padding(.top, 22)
                .padding(.bottom, 32)
            }
            .scrollPosition(id: scrollPosition)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let backAction {
                Button(action: backAction) {
                    Label("Artists", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showsSortMenu {
                    ArtistSortMenu(model: model)
                }
            }
        }
    }

    private var scrollPosition: Binding<ArtistBrowseAnchor?> {
        Binding(
            get: {
                if let scrollScope {
                    return model.artistGridScrollAnchors[scrollScope]
                }
                return nil
            },
            set: {
                if let scrollScope {
                    model.updateArtistsScrollAnchor(
                        $0,
                        scope: scrollScope
                    )
                }
            }
        )
    }

    private var emptyTitle: String {
        model.isArtistSearchActive ? "No Matching Artists" : "No Artists"
    }

    private var emptyDescription: String {
        model.isArtistSearchActive
            ? "Try a different artist name or accepted tag."
            : "Artists will appear here when they are available."
    }
}
