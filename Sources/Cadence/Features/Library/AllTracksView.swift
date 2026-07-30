import SwiftUI

struct AllTracksView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.tracks.isEmpty {
                EmptyLibraryView(
                    title: "No Tracks Yet",
                    description: "Import music to build your library."
                ) {
                    model.requestNavigationDestination(.importMusic)
                }
            } else {
                ScrollView {
                    ProductionTrackTable(
                        model: model,
                        tracks: store.tracks,
                        queueSource: .allTracks,
                        onReachEnd: {
                            await store.loadNextTracks()
                        }
                    )
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(CadenceTheme.contentBackground)
    }

    private var header: some View {
        CadencePageHeader(
            "All Tracks",
            subtitle: "\(store.catalogCounts.liveTrackCount) tracks"
        ) {
            Button("Shuffle", systemImage: "shuffle") {
                guard let first = store.tracks.randomElement() else {
                    return
                }
                model.playProductionTrack(
                    first,
                    within: store.tracks,
                    source: .allTracks,
                    isShuffled: true
                )
            }
            Button("Play", systemImage: "play.fill") {
                guard let first = store.tracks.first else {
                    return
                }
                model.playProductionTrack(
                    first,
                    within: store.tracks,
                    source: .allTracks
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }
}
