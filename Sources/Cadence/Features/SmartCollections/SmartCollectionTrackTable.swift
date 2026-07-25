import SwiftUI

struct SmartCollectionTrackTable: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width - 48, 727)
            let columns = SmartCollectionTrackTableColumnWidths(
                totalWidth: availableWidth - 12
            )

            VStack(spacing: 0) {
                SmartCollectionTrackTableHeader(
                    model: model,
                    columns: columns
                )

                Rectangle()
                    .fill(CadenceTheme.separator)
                    .frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(
                            Array(
                                model.selectedSmartCollectionVisibleTracks
                                    .enumerated()
                            ),
                            id: \.element.id
                        ) { index, track in
                            SmartCollectionTrackTableRow(
                                model: model,
                                track: track,
                                displayIndex: index + 1,
                                columns: columns
                            )
                            .frame(width: columns.total, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
            }
            .frame(width: availableWidth, alignment: .leading)
            .padding(.horizontal, 24)
        }
    }
}

struct SmartCollectionTrackTableColumnWidths: Hashable, Sendable {
    let index: CGFloat
    let title: CGFloat
    let artist: CGFloat
    let album: CGFloat
    let year: CGFloat
    let format: CGFloat
    let duration: CGFloat

    init(totalWidth: CGFloat) {
        let resolvedWidth = max(totalWidth, 700)
        index = 40
        year = 58
        format = 72
        duration = 58

        let flexibleWidth = resolvedWidth - index - year - format - duration
        title = flexibleWidth * 0.34
        artist = flexibleWidth * 0.28
        album = flexibleWidth - title - artist
    }

    var total: CGFloat {
        index + title + artist + album + year + format + duration
    }
}

private struct SmartCollectionTrackTableHeader: View {
    @Bindable var model: CadenceAppModel

    let columns: SmartCollectionTrackTableColumnWidths

    var body: some View {
        HStack(spacing: 0) {
            sortButton(.canonical, alignment: .center)
                .frame(width: columns.index)
            sortButton(.title)
                .frame(width: columns.title)
            sortButton(.artist)
                .frame(width: columns.artist)
            sortButton(.album)
                .frame(width: columns.album)
            sortButton(.year, alignment: .trailing)
                .frame(width: columns.year)
            sortButton(.format)
                .frame(width: columns.format)
            sortButton(.duration, alignment: .trailing)
                .frame(width: columns.duration)
        }
        .frame(height: 38)
    }

    private func sortButton(
        _ field: SmartCollectionSortField,
        alignment: Alignment = .leading
    ) -> some View {
        let descriptor = model.selectedSmartCollectionSortDescriptor
        let isActive = descriptor.field == field

        return Button {
            model.activateSelectedSmartCollectionSort(field)
        } label: {
            HStack(spacing: 4) {
                Text(field.title)
                    .lineLimit(1)

                if isActive, field != .canonical {
                    Image(
                        systemName: descriptor.direction == .ascending
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(.system(size: 8, weight: .bold))
                }
            }
            .font(.caption.weight(isActive ? .semibold : .medium))
            .foregroundStyle(isActive ? .primary : .tertiary)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, field == .canonical ? 0 : 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sortHelp(field: field, descriptor: descriptor))
        .accessibilityLabel("\(field.title) column")
        .accessibilityValue(isActive ? activeSortValue(descriptor) : "Not sorted")
    }

    private func sortHelp(
        field: SmartCollectionSortField,
        descriptor: SmartCollectionSortDescriptor
    ) -> String {
        guard descriptor.field == field else {
            return "Sort by \(field.title)"
        }
        return descriptor.direction == .ascending
            ? "Sorted ascending; click for descending"
            : "Sorted descending; click for ascending"
    }

    private func activeSortValue(
        _ descriptor: SmartCollectionSortDescriptor
    ) -> String {
        descriptor.direction == .ascending
            ? "Sorted ascending"
            : "Sorted descending"
    }
}

private struct SmartCollectionTrackTableRow: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview
    let displayIndex: Int
    let columns: SmartCollectionTrackTableColumnWidths

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            model.selectTrack(track)
        } label: {
            HStack(spacing: 0) {
                indexCell
                    .frame(width: columns.index)
                textCell(track.title, emphasis: isCurrent)
                    .frame(width: columns.title)
                textCell(track.artist)
                    .frame(width: columns.artist)
                textCell(track.album)
                    .frame(width: columns.album)
                trailingCell(track.yearText)
                    .frame(width: columns.year)
                textCell(track.format)
                    .frame(width: columns.format)
                trailingCell(track.durationText)
                    .frame(width: columns.duration)
            }
            .frame(height: 44)
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
                    model.playSelectedSmartCollectionTrack(track)
                }
        )
        .onKeyPress(.return) {
            model.playSelectedSmartCollectionTrack(track)
            return .handled
        }
        .onHover { isHovered = $0 }
        .accessibilityLabel(
            "\(displayIndex), \(track.title), \(track.artist), "
                + "\(track.album), \(track.yearText), \(track.format), "
                + track.durationText
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(
            model.selectedTrackID == track.id ? .isSelected : []
        )
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
            Text(displayIndex.formatted())
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
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
            .lineLimit(1)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 8)
    }

    private var isCurrent: Bool {
        model.currentTrackID == track.id
    }

    private var accessibilityValue: String {
        var states: [String] = []
        if model.selectedTrackID == track.id {
            states.append("Selected")
        }
        if isCurrent {
            states.append(model.isPlaying ? "Playing" : "Paused")
        }
        return states.joined(separator: ", ")
    }
}
