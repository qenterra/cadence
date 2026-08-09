import SwiftUI

struct AllTracksView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @State private var selection: Set<UUID> = []

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
            } else if let window = store.allTracksWindow {
                NativeAllTracksTable(
                    model: model,
                    window: window,
                    repositorySortAction: { sort in
                        await store.sortTracks(sort)
                    },
                    selection: $selection
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            } else {
                ProductionTrackTable(
                    model: model,
                    tracks: store.tracks,
                    queueSource: .allTracks,
                    onReachEnd: {
                        await store.loadNextTracks()
                    },
                    scrollAxes: [.horizontal, .vertical],
                    repositorySortAction: { sort in
                        await store.sortTracks(sort)
                    },
                    selection: $selection
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(CadenceTheme.contentBackground)
        .task(id: trackWindowConfigurationID) {
            await store.allTracksWindow?.configure(
                totalCount: store.catalogCounts.liveTrackCount,
                query: store.trackQuery
            )
        }
    }

    private var trackWindowConfigurationID: String {
        let sort = store.trackQuery.sort
        return "\(store.catalogCounts.liveTrackCount)-\(sort.field.rawValue)-"
            + "\(sort.direction.rawValue)-\(store.trackQuery.search)"
    }

    private var header: some View {
        CadencePageHeader(
            "All Tracks",
            subtitle: "\(store.catalogCounts.liveTrackCount) tracks",
            guideAnchor: .allTracks
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
