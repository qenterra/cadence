import SwiftUI

struct SmartCollectionResultsColumn: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.smartCollectionDraft == nil {
                noSelection
            } else if model.librarySession.store.catalogCounts.liveTrackCount == 0 {
                emptyLibrary
            } else if model.productionSmartCollectionLiveSummary.isEmpty {
                noMatches
            } else {
                results
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.smartCollectionDraft?.name ?? "Live Results")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text(resultCount)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if model.smartCollectionDraft?.rule.children.isEmpty == true {
                Text("All tracks · Add a rule to narrow the collection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !model.smartCollectionValidation.isValid {
                Label(
                    "Preview paused at the last valid rule",
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Updates as the draft changes")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var results: some View {
        if let source = model.productionSmartCollectionLiveTrackSource {
            ProductionTrackTable(
                model: model,
                tracks: source.tracks,
                contentVersion: source.contentVersion,
                context: selectedTrackTableContext,
                showsHeader: false,
                compact: true,
                queueSource: selectedProductionQueueSource,
                onReachEnd: loadNextProductionPage,
                refreshAction: {
                    await model.librarySession.store.refresh(
                        .smartCollections
                    )
                }
            )
            .padding(.bottom, 16)
        } else {
            ProgressView("Loading Results")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var noSelection: some View {
        ContentUnavailableView(
            "No Collection Selected",
            systemImage: "sparkles.rectangle.stack",
            description: Text("Choose a collection to see matching tracks.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatches: some View {
        ContentUnavailableView(
            "No Matching Tracks",
            systemImage: "line.3.horizontal.decrease.circle",
            description: Text("No tracks match the current rules.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Library Is Empty", systemImage: "music.note")
        } description: {
            Text("Import music before building a Smart Collection.")
        } actions: {
            Button("Import Music") {
                model.requestNavigationDestination(.importMusic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultCount: String {
        let count = model.productionSmartCollectionLiveSummary.count
        return "\(count) \(count == 1 ? "track" : "tracks")"
    }

    private var selectedProductionQueueSource: PlaybackQueueSource? {
        model.selectedSmartCollectionID.map {
            .smartCollection($0)
        }
    }

    private var selectedTrackTableContext: TrackTableContext {
        model.selectedSmartCollectionID.map(TrackTableContext.smartCollection)
            ?? .library
    }

    private func loadNextProductionPage() async {
        guard
            let draft = model.smartCollectionDraft,
            model.smartCollectionValidation.isValid
        else {
            return
        }
        await model.librarySession.store.loadNextSmartCollectionResult(
            rule: draft.rule
        )
    }
}
