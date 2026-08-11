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
                    subtitle: "Your library, within reach"
                )

                if store.catalogCounts.liveTrackCount == 0 {
                    EmptyLibraryView(
                        title: "Make Cadence Your Home",
                        description: "Import music to build your listening space."
                    ) {
                        model.requestNavigationDestination(.importMusic)
                    }
                } else {
                    continueListening
                    recentlyPlayed
                    favorites
                    pinnedItems
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CadenceTheme.contentBackground)
    }

    @ViewBuilder
    private var continueListening: some View {
        if let track = HomeListeningSelection.continueTrack(
            from: store.recentlyPlayedTracks
        ) {
            HomeShelf(
                title: "Continue Listening",
                subtitle: "Resume your latest track"
            ) {
                HomeContinueListeningRow(
                    model: model,
                    track: track,
                    queue: store.recentlyPlayedTracks
                )
            }
        }
    }

    private var recentlyPlayed: some View {
        HomeShelf(
            title: "Recently Played",
            subtitle: "Pick up where you left off"
        ) {
            let tracks = HomeListeningSelection.items(
                store.recentlyPlayedTracks,
                limit: 6
            )
            if tracks.isEmpty {
                Text("Play a track and it will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HomeTrackGrid(
                    model: model,
                    tracks: tracks,
                    queueSource: .adHoc
                )
            }
        }
    }
}
