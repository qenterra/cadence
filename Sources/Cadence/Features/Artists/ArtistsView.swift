import SwiftUI

struct ArtistsView: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.librarySession.availability != .preview {
                ProductionArtistsView(
                    model: model,
                    store: model.librarySession.store
                )
            } else if model.tracks.isEmpty {
                EmptyLibraryView(
                    title: "No Artists Yet",
                    description: "Artists will appear here after you import music."
                ) {
                    model.requestNavigationDestination(.importMusic)
                }
            } else if case .detail = model.artistsPresentation {
                if let artist = model.presentedArtist {
                    ArtistDetailView(model: model, artist: artist)
                } else {
                    ArtistsOverview(model: model)
                }
            } else if model.shouldPresentArtistSearchResults {
                searchResults
            } else {
                browseContent
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
        if case .detail = model.artistsPresentation {
            return String(describing: model.artistsPresentation)
        }
        if model.shouldPresentArtistSearchResults {
            return "search"
        }
        return String(describing: model.artistsPresentation)
    }

    private var searchResults: some View {
        ArtistGrid(
            model: model,
            title: "Search Results",
            subtitle: artistCountText(model.visibleArtistSearchResults.count),
            artists: model.visibleArtistSearchResults,
            origin: .search,
            scrollScope: nil,
            showsSortMenu: true
        )
    }

    @ViewBuilder
    private var browseContent: some View {
        switch model.artistsPresentation {
        case .overview, .detail:
            ArtistsOverview(model: model)
        case let .shelf(kind):
            ArtistGrid(
                model: model,
                title: kind.title,
                subtitle: artistCountText(shelfArtists(kind).count),
                artists: shelfArtists(kind),
                origin: .shelf(kind),
                scrollScope: kind,
                showsSortMenu: false,
                backAction: {
                    model.artistsPresentation = .overview
                }
            )
        }
    }

    private func shelfArtists(
        _ kind: ArtistShelfKind
    ) -> [ArtistPreview] {
        switch kind {
        case .recentlyPlayed:
            model.recentlyPlayedArtists
        case .favorites:
            model.favoriteArtists
        }
    }

    private func artistCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "artist" : "artists")"
    }
}
