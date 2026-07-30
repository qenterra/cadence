import SwiftUI

struct SmartCollectionTrackTableRow: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview
    let columns: [TrackTableColumn]
    let widths: SmartCollectionTrackTableWidths

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            song
                .frame(width: widths.song, alignment: .leading)

            ForEach(columns) { column in
                columnValue(column)
                    .frame(
                        width: widths[column],
                        alignment: column == .album ? .leading : .trailing
                    )
            }

            Spacer(minLength: 0)

            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(isHovered ? .primary : .tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .help("Track Actions")
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background {
            if isHovered {
                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .fill(CadenceTheme.hoverFill)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            model.selectTrack(track)
        }
        .onTapGesture(count: 2) {
            model.playSelectedSmartCollectionTrack(track)
        }
        .contextMenu {
            actions
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
                .padding(.leading, 54)
        }
        .accessibilityLabel(
            "\(track.title), \(track.artist), \(track.album), "
                + "\(track.format), \(track.durationText)"
        )
    }

    private var song: some View {
        HStack(spacing: 10) {
            Button {
                model.playSelectedSmartCollectionTrack(track)
            } label: {
                artwork
            }
            .buttonStyle(.plain)
            .help("Play \(track.title)")

            songMetadata
        }
    }

    private var artwork: some View {
        MediaArtworkView(
            source: artworkSource,
            title: track.title,
            placeholder: .track,
            cornerRadius: 6
        )
        .frame(width: 40, height: 40)
        .overlay {
            if isCurrent {
                RoundedRectangle(
                    cornerRadius: 6,
                    style: .continuous
                )
                .fill(.black.opacity(0.34))
                Image(
                    systemName: model.isPlaying
                        ? "waveform"
                        : "speaker.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .symbolEffect(
                    .variableColor.iterative,
                    options: reduceMotion || !model.isPlaying
                        ? .nonRepeating
                        : .repeating
                )
            }
        }
    }

    private var songMetadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(track.title)
                    .font(.callout.weight(isCurrent ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(track.format.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        CadenceTheme.subduedFill,
                        in: Capsule()
                    )
            }

            Button {
                model.requestOpenArtistContextually(id: track.artistID)
            } label: {
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func columnValue(
        _ column: TrackTableColumn
    ) -> some View {
        switch column {
        case .album:
            Button {
                model.requestOpenAlbumContextually(id: track.albumID)
            } label: {
                Text(track.album)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        case .year:
            Text(track.yearText)
        case .dateAdded:
            Text(track.dateAddedText)
        case .playCount:
            Text(track.playCount.formatted())
        case .time:
            Text(track.durationText)
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Play Now", systemImage: "play.fill") {
            model.playSelectedSmartCollectionTrack(track)
        }
        ArtworkMenuItems(
            model: model,
            target: .track(track.id),
            label: "Track Artwork"
        )
        Button("Edit Tags", systemImage: "tag") {
            model.openTagEditor(for: track)
        }
    }

    private var artworkSource: ResolvedArtworkSource {
        track.artworkPalette.map(ResolvedArtworkSource.catalog)
            ?? .placeholder(.track)
    }

    private var isCurrent: Bool {
        model.currentTrackID == track.id
    }
}
