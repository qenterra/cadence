import SwiftUI

struct AlbumGrid: View {
    @Bindable var model: CadenceAppModel

    let title: String
    let subtitle: String
    let albums: [AlbumPreview]
    let origin: AlbumsBrowseOrigin
    let scrollScope: AlbumShelfKind?
    let showsSortMenu: Bool
    var backAction: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let metrics = AlbumsLayoutMetrics(totalWidth: geometry.size.width)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header

                    if albums.isEmpty {
                        ContentUnavailableView {
                            Label(
                                emptyTitle,
                                systemImage: "rectangle.stack"
                            )
                        } description: {
                            Text(emptyDescription)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    } else {
                        AlbumTileGrid(
                            model: model,
                            albums: albums,
                            metrics: metrics,
                            origin: origin
                        )
                    }
                }
                .padding(.horizontal, AlbumsLayoutMetrics.horizontalPadding)
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
                    Label("Albums", systemImage: "chevron.left")
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
                    AlbumSortMenu(model: model)
                }
            }
        }
    }

    private var scrollPosition: Binding<AlbumBrowseAnchor?> {
        Binding(
            get: {
                if let scrollScope {
                    return model.albumGridScrollAnchors[scrollScope]
                }
                return nil
            },
            set: {
                if let scrollScope {
                    model.updateAlbumsScrollAnchor(
                        $0,
                        scope: scrollScope
                    )
                }
            }
        )
    }

    private var emptyTitle: String {
        model.isAlbumSearchActive ? "No Matching Albums" : "No Albums"
    }

    private var emptyDescription: String {
        model.isAlbumSearchActive
            ? "Try a different album, artist, or assigned album tag."
            : "Albums will appear here when they are available."
    }
}
