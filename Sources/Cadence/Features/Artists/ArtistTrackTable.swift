import SwiftUI

struct ArtistTrackTable: View {
    @Bindable var model: CadenceAppModel

    let artist: ArtistPreview
    let totalWidth: CGFloat

    var body: some View {
        let availableWidth = max(totalWidth, 760)
        let columns = ArtistTrackTableColumnWidths(
            totalWidth: availableWidth
        )
        let tracks = model.canonicalTracks(for: artist)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("All Tracks")
                    .font(.title3.bold())

                Text(tracks.count.formatted())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ArtistTrackTableHeader(columns: columns)

                Rectangle()
                    .fill(CadenceTheme.separator)
                    .frame(height: 1)

                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(tracks) { track in
                        ArtistTrackRow(
                            model: model,
                            artist: artist,
                            track: track,
                            columns: columns
                        )
                        .frame(width: columns.total, alignment: .leading)
                    }
                }
                .padding(.vertical, 5)
            }
            .frame(width: columns.total, alignment: .leading)
        }
    }
}

private struct ArtistTrackTableHeader: View {
    let columns: ArtistTrackTableColumnWidths

    var body: some View {
        HStack(spacing: 0) {
            header("#", alignment: .center)
                .frame(width: columns.index)
            header("Title")
                .frame(width: columns.title)
            header("Album")
                .frame(width: columns.album)
            header("Format")
                .frame(width: columns.format)
            header("Time", alignment: .trailing)
                .frame(width: columns.duration)
            Color.clear
                .frame(width: columns.actions)
        }
        .frame(height: 38)
    }

    private func header(
        _ title: String,
        alignment: Alignment = .leading
    ) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, title == "#" ? 0 : 8)
    }
}

private struct ArtistTrackRow: View {
    @Bindable var model: CadenceAppModel

    let artist: ArtistPreview
    let track: TrackPreview
    let columns: ArtistTrackTableColumnWidths

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @State private var showsTags = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                model.selectTrack(track)
            } label: {
                HStack(spacing: 0) {
                    indexCell
                        .frame(width: columns.index)
                    textCell(track.title, emphasis: isCurrent)
                        .frame(width: columns.title)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(CadenceRowButtonStyle())
            .focused($isFocused)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        model.playArtistTrack(track, in: artist)
                    }
            )
            .onKeyPress(.return) {
                model.playArtistTrack(track, in: artist)
                return .handled
            }
            .accessibilityLabel(
                "\(track.trackNumber), \(track.title), \(track.album), "
                    + "\(track.format), \(track.durationText)"
            )
            .accessibilityValue(accessibilityValue)

            MediaMetadataLink(
                track.album,
                accessibilityLabel: "Open album \(track.album)"
            ) {
                model.requestOpenAlbumContextually(id: track.albumID)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(width: columns.album, height: 44, alignment: .leading)

            Button {
                model.selectTrack(track)
            } label: {
                HStack(spacing: 0) {
                    textCell(track.format)
                        .frame(width: columns.format)
                    trailingCell(track.durationText)
                        .frame(width: columns.duration)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(CadenceRowButtonStyle())
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        model.playArtistTrack(track, in: artist)
                    }
            )

            Button {
                showsTags.toggle()
            } label: {
                Image(systemName: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: columns.actions, height: 44)
                    .contentShape(Rectangle())
                    .opacity(showsTagAction ? 1 : 0)
            }
            .buttonStyle(.plain)
            .disabled(!showsTagAction)
            .help("View Track Tags")
            .popover(isPresented: $showsTags, arrowEdge: .trailing) {
                TrackTagPopover(
                    model: model,
                    track: track,
                    dismiss: {
                        showsTags = false
                    }
                )
            }
        }
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
            ArtworkMenuItems(
                model: model,
                target: .track(track.id),
                label: "Track Artwork"
            )

            Button("Edit Tags", systemImage: "tag") {
                model.openTagEditor(for: track)
            }
        }
    }

    @ViewBuilder
    private var indexCell: some View {
        if isCurrent {
            Image(systemName: model.isPlaying ? "waveform" : "speaker.fill")
                .font(.caption)
                .foregroundStyle(.primary)
                .symbolEffect(
                    .variableColor.iterative,
                    options: reduceMotion || !model.isPlaying
                        ? .nonRepeating
                        : .repeating
                )
        } else {
            Text(track.trackNumber.formatted())
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private var isCurrent: Bool {
        model.currentTrackID == track.id
    }

    private var showsTagAction: Bool {
        isHovered
            || isFocused
            || showsTags
            || model.selectedTrackID == track.id
            || isCurrent
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if model.selectedTrackID == track.id {
            values.append("Selected")
        }
        if isCurrent {
            values.append(model.isPlaying ? "Playing" : "Current track, paused")
        }
        return values.joined(separator: ", ")
    }

    private func textCell(
        _ text: String,
        emphasis: Bool = false
    ) -> some View {
        Text(text)
            .font(.callout.weight(emphasis ? .semibold : .regular))
            .foregroundStyle(emphasis ? .primary : .secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }

    private func trailingCell(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 8)
    }
}
