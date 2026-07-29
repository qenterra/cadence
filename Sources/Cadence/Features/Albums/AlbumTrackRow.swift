import SwiftUI

struct AlbumTrackRow: View {
    @Bindable var model: CadenceAppModel

    let album: AlbumPreview
    let track: TrackPreview
    let columns: AlbumTrackTableColumnWidths

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
                    textCell(track.format)
                        .frame(width: columns.format)
                    trailingCell(track.durationText)
                        .frame(width: columns.duration)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(CadenceRowButtonStyle())
            .focused($isFocused)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        model.playAlbumTrack(track, in: album)
                    }
            )
            .onKeyPress(.return) {
                model.playAlbumTrack(track, in: album)
                return .handled
            }
            .accessibilityLabel(
                "\(track.trackNumber), \(track.title), \(track.format), "
                    + track.durationText
            )
            .accessibilityValue(accessibilityValue)

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
