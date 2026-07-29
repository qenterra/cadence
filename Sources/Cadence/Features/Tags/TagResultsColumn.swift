import SwiftUI

struct TagResultsColumn: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            resultsHeader

            ZStack {
                if model.selectedTag == nil {
                    noSelection
                } else {
                    results
                }
            }
            .id(resultListID)
            .transition(.opacity)
            .animation(columnTransition, value: resultListID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onKeyPress("a", phases: .down) { keyPress in
            guard
                keyPress.modifiers == .command,
                model.canSelectAllTagResults
            else {
                return .ignored
            }

            model.selectAllTagResults()
            return .handled
        }
    }

    private var resultsHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            if model.hasContextualBackNavigation {
                Button {
                    model.requestContextualBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Back to \(model.contextualBackTitle)")
                .accessibilityLabel(
                    "Back to \(model.contextualBackTitle)"
                )
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTagDisplayPath)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                if model.selectedTag != nil {
                    Text(resultsSummary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                Button {
                    model.toggleTagInspector()
                } label: {
                    Label("Edit Tags", systemImage: "tag")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.tagEditingSelection.isEmpty)
                .help("Edit Tags (⌥⌘T)")

                Picker("Result Scope", selection: tagResultScopeBinding) {
                    ForEach(TagResultScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 148)
                .accessibilityLabel("Tag result scope")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var results: some View {
        switch model.tagResultScope {
        case .tracks:
            if model.taggedTracks.isEmpty {
                noMatches(scope: "tracks")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.taggedTracks.enumerated()), id: \.element.id) { index, result in
                            TagResultTrackRow(
                                model: model,
                                result: result,
                                trackNumber: index + 1
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
            }
        case .albums:
            if model.taggedAlbums.isEmpty {
                noMatches(scope: "albums")
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.taggedAlbums) { result in
                            TagResultAlbumRow(model: model, result: result)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var noSelection: some View {
        ContentUnavailableView(
            "No Tag Selected",
            systemImage: "tag",
            description: Text("Choose a tag to see matching music.")
        )
    }

    private func noMatches(scope: String) -> some View {
        ContentUnavailableView(
            "No Matching \(scope.localizedCapitalized)",
            systemImage: model.tagResultScope == .tracks ? "music.note" : "square.stack",
            description: Text(
                "No \(scope) use \(selectedTagDisplayPath)."
            )
        )
    }

    private var selectedTagDisplayPath: String {
        model.selectedTag?.displayPath ?? "Tags"
    }

    private var resultListID: String {
        "\(model.selectedTagID ?? "none")-\(model.tagResultScope.rawValue)"
    }

    private var resultsSummary: String {
        let matches = "\(model.taggedTracks.count) tracks · "
            + "\(model.taggedAlbums.count) albums"
        guard !model.tagEditingSelection.isEmpty else {
            return matches
        }
        return "\(model.tagEditingSelection.count) selected · \(matches)"
    }

    private var tagResultScopeBinding: Binding<TagResultScope> {
        Binding(
            get: { model.tagResultScope },
            set: model.selectTagResultScope
        )
    }

    private var columnTransition: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }
}
