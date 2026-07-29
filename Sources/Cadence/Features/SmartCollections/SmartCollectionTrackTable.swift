import SwiftUI

struct SmartCollectionTrackTable: View {
    @Bindable var model: CadenceAppModel

    @AppStorage("trackTable.visibleColumns")
    private var visibleColumnsRaw = TrackTableColumn.defaultRawValue

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header

                ForEach(
                    model.selectedSmartCollectionVisibleTracks
                ) { track in
                    SmartCollectionTrackTableRow(
                        model: model,
                        track: track,
                        columns: visibleColumns
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            sortButton(
                title: "Song",
                field: .title,
                alignment: .leading
            )
            .frame(maxWidth: .infinity)

            ForEach(visibleColumns) { column in
                sortButton(
                    title: column.title,
                    field: sortField(for: column),
                    alignment: column == .album ? .leading : .trailing
                )
                .frame(
                    width: width(for: column)
                )
            }

            Menu {
                Text("Columns")
                ForEach(TrackTableColumn.allCases) { column in
                    Toggle(
                        column.title,
                        isOn: visibilityBinding(for: column)
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .help("Choose Columns")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
        }
    }

    private func sortButton(
        title: String,
        field: SmartCollectionSortField,
        alignment: Alignment
    ) -> some View {
        let descriptor = model.selectedSmartCollectionSortDescriptor
        let isActive = descriptor.field == field

        return Button {
            model.activateSelectedSmartCollectionSort(field)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if isActive {
                    Image(
                        systemName: descriptor.direction == .ascending
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(.system(size: 8, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isActive ? "Sorted" : "Not sorted")
    }

    private var visibleColumns: [TrackTableColumn] {
        TrackTableColumn.decode(visibleColumnsRaw)
    }

    private func visibilityBinding(
        for column: TrackTableColumn
    ) -> Binding<Bool> {
        Binding(
            get: { visibleColumns.contains(column) },
            set: { isVisible in
                var columns = Set(visibleColumns)
                if isVisible {
                    columns.insert(column)
                } else {
                    columns.remove(column)
                }
                visibleColumnsRaw = TrackTableColumn.encode(columns)
            }
        )
    }

    private func sortField(
        for column: TrackTableColumn
    ) -> SmartCollectionSortField {
        switch column {
        case .album: .album
        case .year: .year
        case .dateAdded: .dateAdded
        case .playCount: .playCount
        case .time: .duration
        }
    }
}

private struct SmartCollectionTrackTableRow: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview
    let columns: [TrackTableColumn]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            song
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(columns) { column in
                columnValue(column)
                    .frame(
                        width: width(for: column),
                        alignment: column == .album ? .leading : .trailing
                    )
            }

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
        .background(isHovered ? CadenceTheme.hoverFill : .clear)
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
            .buttonStyle(.plain)
            .help("Play \(track.title)")

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

private func width(
    for column: TrackTableColumn
) -> CGFloat {
    switch column {
    case .album: 190
    case .dateAdded: 100
    case .year, .playCount, .time: 58
    }
}
