import SwiftUI

struct AlbumsView: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.isAlbumSearchActive {
                AlbumGrid(
                    model: model,
                    title: "Search Results",
                    subtitle: searchSubtitle,
                    albums: model.visibleAlbumSearchResults,
                    origin: .search,
                    scrollScope: nil,
                    showsSortMenu: true
                )
            } else {
                switch model.albumsPresentation {
                case .overview:
                    AlbumsOverview(model: model)
                case let .shelf(kind):
                    AlbumGrid(
                        model: model,
                        title: kind.title,
                        subtitle: shelfSubtitle(kind),
                        albums: shelfAlbums(kind),
                        origin: .shelf(kind),
                        scrollScope: kind,
                        showsSortMenu: false,
                        backAction: {
                            model.albumsPresentation = .overview
                        }
                    )
                case .detail:
                    if let album = model.presentedAlbum {
                        AlbumDetailView(model: model, album: album)
                    } else {
                        AlbumsOverview(model: model)
                    }
                }
            }
        }
        .id(routeIdentity)
        .transition(.opacity)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.15),
            value: routeIdentity
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.contentBackground)
    }

    private var routeIdentity: String {
        if model.isAlbumSearchActive {
            return "search"
        }
        return String(describing: model.albumsPresentation)
    }

    private var searchSubtitle: String {
        let count = model.visibleAlbumSearchResults.count
        return "\(count) \(count == 1 ? "album" : "albums")"
    }

    private func shelfAlbums(_ kind: AlbumShelfKind) -> [AlbumPreview] {
        switch kind {
        case .recentlyAdded:
            model.recentlyAddedAlbums
        case .favorites:
            model.favoriteAlbums
        }
    }

    private func shelfSubtitle(_ kind: AlbumShelfKind) -> String {
        let count = shelfAlbums(kind).count
        return "\(count) \(count == 1 ? "album" : "albums")"
    }
}
