import SwiftUI

struct ProductionHomeView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @AppStorage("home.pins.revision") var pinRevision = 0

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 30) {
                CadencePageHeader(
                    "Home",
                    subtitle: "\(store.catalogCounts.liveTrackCount) tracks"
                )

                if store.availability == .loading,
                   store.catalogCounts.liveTrackCount == 0 {
                    ProgressView("Loading Home")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if store.catalogCounts.liveTrackCount == 0 {
                    EmptyLibraryView(
                        title: "No Music Yet",
                        description: "Import music to start building your library."
                    ) {
                        model.requestNavigationDestination(.importMusic)
                    }
                } else {
                    pinnedItems
                    recentlyPlayed
                    favorites
                    personalizationEmptyState
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CadenceTheme.contentBackground)
    }

    @ViewBuilder
    private var recentlyPlayed: some View {
        let tracks = HomeListeningSelection.recentItems(
            store.recentlyPlayedTracks,
            excludingID: model.currentPlaybackTrack?.id,
            limit: 6
        )
        if !tracks.isEmpty {
            HomeShelf(title: "Recently Played") {
                HomeTrackGrid(
                    model: model,
                    tracks: tracks,
                    queueSource: .adHoc
                )
            }
        }
    }

    @ViewBuilder
    private var personalizationEmptyState: some View {
        if !hasPinnedItems,
           !hasRecentItems,
           store.favoriteTracks.isEmpty,
           store.favoriteAlbums.isEmpty,
           store.favoriteArtists.isEmpty {
            ContentUnavailableView {
                Label("Start Listening", systemImage: "waveform")
            } description: {
                Text("Recently played music, favorites, and shortcuts will appear here.")
            } actions: {
                Button("Browse All Tracks") {
                    model.requestNavigationDestination(.allTracks)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        }
    }

    private var hasRecentItems: Bool {
        !HomeListeningSelection.recentItems(
            store.recentlyPlayedTracks,
            excludingID: model.currentPlaybackTrack?.id,
            limit: 1
        ).isEmpty
    }
}
