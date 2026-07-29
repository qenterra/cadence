import SwiftUI

struct TracksColumn: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            LibraryColumnHeader(
                title: model.isShowingLibrarySearchResults ? "Search Results" : "Tracks",
                detail: model.visibleTracks.count.formatted()
            )

            ZStack {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.visibleTracks.enumerated()), id: \.element.id) { index, track in
                            TrackBrowserRow(
                                model: model,
                                track: track,
                                trackNumber: index + 1
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .id(trackListID)
                .transition(.opacity)
            }
            .animation(columnTransition, value: trackListID)

            if !model.isShowingLibrarySearchResults, let track = model.selectedTrack {
                Divider()
                TrackSummaryView(model: model, track: track)
            }
        }
    }

    private var trackListID: String {
        if model.isShowingLibrarySearchResults {
            return "search"
        }
        return model.selectedAlbumID ?? "empty"
    }

    private var columnTransition: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }
}

private struct TrackBrowserRow: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview
    let trackNumber: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.selectTrack(track)
            } label: {
                trackLabel
            }
            .buttonStyle(CadenceRowButtonStyle())
            .focused($isFocused)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        model.play(track)
                    }
            )

            trackMenu
                .opacity(showsTrackMenu ? 1 : 0)
                .allowsHitTesting(showsTrackMenu)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background {
            BrowserRowSurface(
                isSelected: model.selectedTrackID == track.id,
                isHovered: isHovered,
                isFocused: isFocused
            )
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            trackActions
        }
    }

    private var trackLabel: some View {
        HStack(spacing: 10) {
            trackStatus
                .font(.caption)
                .frame(width: 24)

            Text(track.title)
                .font(.body.weight(isCurrentTrack ? .medium : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(track.durationText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(trackNumber), \(track.title), \(track.durationText)")
        .accessibilityValue(accessibilityState)
    }

    @ViewBuilder
    private var trackStatus: some View {
        if isCurrentTrack {
            if model.isPlaying, !reduceMotion {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative)
                    .foregroundStyle(.tint)
            } else if model.isPlaying {
                Image(systemName: "waveform")
                    .foregroundStyle(.tint)
            } else {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(trackNumber.formatted())
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private var trackMenu: some View {
        Menu {
            trackActions
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Track Actions")
    }

    private var isCurrentTrack: Bool {
        model.currentTrackID == track.id
    }

    private var showsTrackMenu: Bool {
        isHovered
            || isFocused
            || model.selectedTrackID == track.id
            || isCurrentTrack
    }

    private var accessibilityState: String {
        var states: [String] = []
        if model.selectedTrackID == track.id {
            states.append("Selected")
        }
        if isCurrentTrack {
            states.append(model.isPlaying ? "Playing" : "Paused")
        }
        return states.joined(separator: ", ")
    }

    @ViewBuilder
    private var trackActions: some View {
        Button("Play", systemImage: "play.fill") {
            model.play(track)
        }

        Button(
            model.isFavorite(track) ? "Remove from Favorites" : "Add to Favorites",
            systemImage: model.isFavorite(track) ? "heart.slash" : "heart"
        ) {
            model.toggleFavorite(track)
        }

        Divider()

        ArtworkMenuItems(
            model: model,
            target: .track(track.id),
            label: "Track Artwork"
        )

        Divider()

        Button("Show in Finder", systemImage: "folder") {}
            .disabled(true)

        Button("Technical Details", systemImage: "info.circle") {}
            .disabled(true)
    }
}

private struct TrackSummaryView: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview

    var body: some View {
        HStack(spacing: 14) {
            MediaArtworkView(
                source: model.resolvedArtwork(for: track),
                title: track.album,
                placeholder: .track,
                cornerRadius: 7
            )
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)

                MediaMetadataLink(
                    track.artist,
                    accessibilityLabel: "Open artist \(track.artist)"
                ) {
                    model.requestOpenArtistContextually(id: track.artistID)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    MediaMetadataLink(
                        track.album,
                        accessibilityLabel: "Open album \(track.album)"
                    ) {
                        model.requestOpenAlbumContextually(id: track.albumID)
                    }

                    Text(
                        " · \(track.yearText) · \(track.durationText)"
                            + " · \(track.format)"
                    )
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .help(track.libraryPreviewMetadataText)

                trackTags
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Button {
                    model.openTagEditor(for: track)
                } label: {
                    Image(systemName: "tag")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Edit Tags for \(track.title)")
                .accessibilityLabel("Edit Tags for \(track.title)")

                Button {
                    model.toggleFavorite(track)
                } label: {
                    Image(
                        systemName: model.isFavorite(track)
                            ? "heart.fill"
                            : "heart"
                    )
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(favoriteActionTitle)
                .accessibilityLabel(favoriteActionTitle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 96)
    }

    @ViewBuilder
    private var trackTags: some View {
        let tags = model.effectiveTags(for: track)
        if tags.isEmpty {
            Label("No tags", systemImage: "tag")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 5) {
                Image(systemName: "tag")

                ForEach(tags.prefix(3)) { tag in
                    MediaMetadataLink(
                        tag.displayPath,
                        accessibilityLabel:
                        "Show tracks tagged \(tag.displayPath)"
                    ) {
                        model.requestOpenTagContextually(tag)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
    }

    private var favoriteActionTitle: String {
        model.isFavorite(track)
            ? "Remove \(track.title) from Favorites"
            : "Add \(track.title) to Favorites"
    }
}
