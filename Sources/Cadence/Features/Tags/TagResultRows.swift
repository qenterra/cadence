import AppKit
import SwiftUI

struct TagResultTrackRow: View {
    @Bindable var model: CadenceAppModel

    let result: TaggedTrackPreview
    let trackNumber: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            trackStatus
                .font(.caption)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    model.updateTagEditingSelection(
                        currentTagSelectionGesture(),
                        target: .track(result.track.id)
                    )
                } label: {
                    Text(result.track.title)
                        .font(
                            .body.weight(
                                isCurrentTrack ? .medium : .regular
                            )
                        )
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CadenceRowButtonStyle())
                .focused($isFocused)
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            model.play(result.track)
                        }
                )

                MediaMetadataLink(
                    result.track.artist,
                    accessibilityLabel:
                    "Open artist \(result.track.artist)"
                ) {
                    model.requestOpenArtistContextually(
                        id: result.track.artistID
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                MediaMetadataLink(
                    result.track.album,
                    accessibilityLabel:
                    "Open album \(result.track.album)"
                ) {
                    model.requestOpenAlbumContextually(
                        id: result.track.albumID
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(
                    result.source.title,
                    systemImage: result.source.symbolName
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            .frame(maxWidth: 170, alignment: .trailing)

            Text(result.track.durationText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background {
            BrowserRowSurface(
                isSelected: isSelected,
                isHovered: isHovered,
                isFocused: isFocused
            )
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Edit Tags", systemImage: "tag") {
                model.openTagInspector(for: .track(result.track.id))
            }

            ArtworkMenuItems(
                model: model,
                target: .track(result.track.id),
                label: "Track Artwork"
            )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

    private var isCurrentTrack: Bool {
        model.currentTrackID == result.track.id
    }

    private var isSelected: Bool {
        model.tagEditingSelection.contains(.track(result.track.id))
    }

    private var accessibilityState: String {
        var states = [result.source.title]
        if isPrimarySelection {
            states.append("Primary selection")
        } else if isSelected {
            states.append("Selected")
        }
        if isCurrentTrack {
            states.append(model.isPlaying ? "Playing" : "Paused")
        }
        return states.joined(separator: ", ")
    }

    private var isPrimarySelection: Bool {
        model.tagEditingSelection.primaryTarget == .track(result.track.id)
    }
}

struct TagResultAlbumRow: View {
    @Bindable var model: CadenceAppModel

    let result: TaggedAlbumPreview

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            model.updateTagEditingSelection(
                currentTagSelectionGesture(),
                target: .album(result.album.id)
            )
        } label: {
            HStack(spacing: 13) {
                MediaArtworkView(
                    source: model.resolvedArtwork(for: result.album),
                    title: result.album.title,
                    placeholder: .album,
                    cornerRadius: 7
                )
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.album.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(result.album.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(albumMetadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Label(result.source.title, systemImage: result.source.symbolName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 72)
            .background {
                BrowserRowSurface(
                    isSelected: isSelected,
                    isHovered: isHovered,
                    isFocused: isFocused
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(CadenceRowButtonStyle())
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Edit Tags", systemImage: "tag") {
                model.openTagInspector(for: .album(result.album.id))
            }
        }
        .accessibilityLabel(
            "\(result.album.title), \(result.album.artist), \(result.album.trackCount) tracks"
        )
        .accessibilityValue(accessibilityState(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isSelected: Bool {
        model.tagEditingSelection.contains(.album(result.album.id))
    }

    private func accessibilityState(isSelected: Bool) -> String {
        var states = [result.source.title]
        if model.tagEditingSelection.primaryTarget == .album(result.album.id) {
            states.append("Primary selection")
        } else if isSelected {
            states.append("Selected")
        }
        return states.joined(separator: ", ")
    }

    private var albumMetadata: String {
        let trackLabel = result.album.trackCount == 1 ? "track" : "tracks"
        return "\(result.album.year) · \(result.album.trackCount) \(trackLabel)"
    }
}

private func currentTagSelectionGesture() -> TagSelectionGesture {
    let modifiers = NSEvent.modifierFlags
    if modifiers.contains(.shift) {
        return .range
    }
    if modifiers.contains(.command) {
        return .toggle
    }
    return .replace
}

private extension TrackTagMatchSource {
    var symbolName: String {
        switch self {
        case .direct:
            "tag.fill"
        case .inherited:
            "arrow.down.to.line"
        }
    }
}

private extension AlbumTagMatchSource {
    var symbolName: String {
        switch self {
        case .album:
            "square.stack.fill"
        case .track:
            "music.note"
        }
    }
}
