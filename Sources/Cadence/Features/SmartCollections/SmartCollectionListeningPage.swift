import SwiftUI

struct SmartCollectionListeningPage: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.selectedSmartCollection == nil {
                noSelection
            } else {
                SmartCollectionListeningHeader(model: model)

                Rectangle()
                    .fill(CadenceTheme.separator)
                    .frame(height: 1)

                if selectedTracksAreEmpty {
                    noMatches
                } else if isProduction {
                    ScrollView {
                        ProductionTrackTable(
                            model: model,
                            tracks: model.selectedProductionSmartCollectionTracks,
                            queueSource: selectedProductionQueueSource,
                            onReachEnd: loadNextProductionPage
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                } else {
                    SmartCollectionTrackTable(model: model)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var noSelection: some View {
        ContentUnavailableView {
            Label(
                "No Smart Collection Selected",
                systemImage: "sparkles.rectangle.stack"
            )
        } description: {
            Text("Choose a collection, or create one from the sidebar.")
        } actions: {
            Button("New Collection") {
                model.requestNewSmartCollection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatches: some View {
        ContentUnavailableView {
            Label("No Matching Tracks", systemImage: "music.note.list")
        } description: {
            Text("Edit the rules to include tracks in this collection.")
        } actions: {
            Button("Edit Rules") {
                model.requestEditSelectedSmartCollection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isProduction: Bool {
        model.librarySession.availability != .preview
    }

    private var selectedTracksAreEmpty: Bool {
        if isProduction {
            return model.selectedProductionSmartCollectionSummary.isEmpty
        }
        return model.selectedSmartCollectionCanonicalTracks.isEmpty
    }

    private var selectedProductionQueueSource: PlaybackQueueSource? {
        model.selectedSmartCollectionID.map {
            .smartCollection($0)
        }
    }

    private func loadNextProductionPage() async {
        guard let rule = model.selectedSmartCollection?.rule else {
            return
        }
        await model.librarySession.store.loadNextSmartCollectionResult(
            rule: rule
        )
    }
}
