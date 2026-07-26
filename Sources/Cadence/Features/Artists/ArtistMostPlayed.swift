import SwiftUI

struct ArtistMostPlayed: View {
    @Bindable var model: CadenceAppModel

    let artist: ArtistPreview

    var body: some View {
        let tracks = model.mostPlayedTracks(for: artist)

        VStack(alignment: .leading, spacing: 12) {
            Text("Most Played")
                .font(.title3.bold())

            if tracks.isEmpty {
                Text("No tracks are available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        ArtistMostPlayedRow(
                            model: model,
                            artist: artist,
                            track: track,
                            rank: index + 1
                        )
                    }
                }
            }
        }
    }
}

private struct ArtistMostPlayedRow: View {
    @Bindable var model: CadenceAppModel

    let artist: ArtistPreview
    let track: TrackPreview
    let rank: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(
                        systemName: model.isPlaying
                            ? "waveform"
                            : "speaker.fill"
                    )
                    .symbolEffect(
                        .variableColor.iterative,
                        options: reduceMotion || !model.isPlaying
                            ? .nonRepeating
                            : .repeating
                    )
                } else {
                    Text(rank.formatted())
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(isCurrent ? .primary : .tertiary)
            .frame(width: 24)

            MediaArtworkView(
                source: model.resolvedArtwork(for: track),
                title: track.album,
                placeholder: .track,
                cornerRadius: 5
            )
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    model.selectTrack(track)
                } label: {
                    Text(track.title)
                        .font(.callout.weight(isCurrent ? .semibold : .medium))
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
                            model.playArtistTrack(track, in: artist)
                        }
                )
                .onKeyPress(.return) {
                    model.playArtistTrack(track, in: artist)
                    return .handled
                }

                MediaMetadataLink(
                    track.album,
                    accessibilityLabel: "Open album \(track.album)"
                ) {
                    model.requestOpenAlbumContextually(id: track.albumID)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(track.durationText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(height: 58)
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
        .accessibilityLabel(
            "\(rank), \(track.title), \(track.album), \(track.durationText)"
        )
        .accessibilityValue(
            isCurrent
                ? (model.isPlaying ? "Playing" : "Current track, paused")
                : ""
        )
    }

    private var isCurrent: Bool {
        model.currentTrackID == track.id
    }
}
