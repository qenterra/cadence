import SwiftUI

struct AllTracksView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.availability == .loading,
               store.catalogCounts.liveTrackCount == 0 {
                ProgressView("Loading Tracks")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.catalogCounts.liveTrackCount == 0 {
                EmptyLibraryView(
                    title: "No Tracks Yet",
                    description: "Import music to build your library."
                ) {
                    model.requestNavigationDestination(.importMusic)
                }
            } else if let window = store.allTracksWindow {
                windowContent(window)
            } else {
                ProductionTrackTable(
                    model: model,
                    tracks: store.tracks,
                    queueSource: .allTracks,
                    onReachEnd: {
                        await store.loadNextTracks()
                    },
                    repositorySortAction: { sort in
                        await store.sortTracks(sort)
                    },
                    selection: $selection
                )
                .padding(.horizontal, CadenceLayout.pageInset)
                .padding(.bottom, CadenceLayout.pageInset)
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

    @ViewBuilder
    private func windowContent(_ window: LibraryTrackWindow) -> some View {
        switch window.firstPageState {
        case .idle, .loading:
            ProgressView("Loading Tracks")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView(
                "Couldn’t Load Tracks",
                systemImage: "exclamationmark.triangle",
                description: Text(
                    ProductErrorMessage(
                        detail: message,
                        preservedState: String(localized: "Your library is unchanged."),
                        recoveryAction: String(localized: "Try again.")
                    ).text
                )
            )
            .overlay(alignment: .bottom) {
                Button("Try Again") {
                    Task {
                        await window.retryFirstPage()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, CadenceLayout.sectionGap)
            }
        case .ready:
            NativeAllTracksTable(
                model: model,
                window: window,
                repositorySortAction: { sort in
                    await store.sortTracks(sort)
                },
                selection: $selection
            )
            .padding(.horizontal, CadenceLayout.pageInset)
            .padding(.bottom, CadenceLayout.pageInset)
        }
    }

    private var trackWindowConfigurationID: String {
        let sort = store.trackQuery.sort
        return "\(store.catalogCounts.liveTrackCount)-\(sort.field.rawValue)-"
            + "\(sort.direction.rawValue)-\(store.trackQuery.search)"
    }

    private var header: some View {
        CadencePageHeader(
            "Tracks",
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
            .disabled(store.tracks.isEmpty)
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
            .disabled(store.tracks.isEmpty)
        }
        .padding(.horizontal, CadenceLayout.pageInset)
        .padding(.top, CadenceLayout.pageInset)
        .padding(.bottom, CadenceLayout.contentGap)
    }
}
