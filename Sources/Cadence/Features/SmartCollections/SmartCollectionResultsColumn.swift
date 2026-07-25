import SwiftUI

struct SmartCollectionResultsColumn: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.smartCollectionDraft == nil {
                noSelection
            } else if model.tracks.isEmpty {
                emptyLibrary
            } else if model.smartCollectionLiveTracks.isEmpty {
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

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.smartCollectionLiveTracks) { track in
                    SmartCollectionResultTrackRow(
                        model: model,
                        track: track
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
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
            Text("Import a folder before building a Smart Collection.")
        } actions: {
            Button("Import Folder") {
                model.requestNavigationDestination(.importFolder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultCount: String {
        let count = model.smartCollectionLiveTracks.count
        return "\(count) \(count == 1 ? "track" : "tracks")"
    }
}

private struct SmartCollectionResultTrackRow: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            model.selectTrack(track)
        } label: {
            HStack(spacing: 10) {
                trackStatus
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(track.title)
                            .font(.body.weight(isCurrent ? .medium : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(track.durationText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !effectiveTagText.isEmpty {
                        Label(effectiveTagText, systemImage: "tag")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 62)
            .background {
                BrowserRowSurface(
                    isSelected: model.selectedTrackID == track.id,
                    isHovered: isHovered,
                    isFocused: isFocused
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CadenceRowButtonStyle())
        .focused($isFocused)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    model.play(track)
                }
        )
        .onHover { isHovered = $0 }
        .accessibilityLabel(
            "\(track.title), \(track.artist), \(track.album), "
                + "\(track.yearText), \(track.durationText)"
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(
            model.selectedTrackID == track.id ? .isSelected : []
        )
    }

    @ViewBuilder
    private var trackStatus: some View {
        if isCurrent, model.isPlaying, !reduceMotion {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative)
                .foregroundStyle(.tint)
        } else if isCurrent, model.isPlaying {
            Image(systemName: "waveform")
                .foregroundStyle(.tint)
        } else if isCurrent {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "music.note")
                .foregroundStyle(.tertiary)
        }
    }

    private var isCurrent: Bool {
        model.currentTrackID == track.id
    }

    private var metadata: String {
        "\(track.artist) · \(track.album) · \(track.yearText)"
    }

    private var effectiveTagText: String {
        model.effectiveTags(for: track)
            .map(\.displayPath)
            .joined(separator: " · ")
    }

    private var accessibilityValue: String {
        var states: [String] = []
        if model.selectedTrackID == track.id {
            states.append("Selected")
        }
        if isCurrent {
            states.append(model.isPlaying ? "Playing" : "Paused")
        }
        if !effectiveTagText.isEmpty {
            states.append("Tags \(effectiveTagText)")
        }
        return states.joined(separator: ", ")
    }
}
