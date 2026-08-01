import AppKit
import SwiftUI

enum TrackTableSortField: String, CaseIterable {
    case song
    case album
    case year
    case dateAdded
    case playCount
    case time

    var title: String {
        switch self {
        case .song: "Song"
        case .album: "Album"
        case .year: "Year"
        case .dateAdded: "Date Added"
        case .playCount: "Plays"
        case .time: "Time"
        }
    }
}

enum TrackTableSortDirection: String {
    case ascending
    case descending

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

struct TrackTableSortDescriptor {
    let field: TrackTableSortField
    let direction: TrackTableSortDirection

    func sorted(
        _ tracks: [LibraryTrackProjection]
    ) -> [LibraryTrackProjection] {
        tracks.sorted { lhs, rhs in
            let order = compare(lhs, rhs)
            if order == .orderedSame {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return direction == .ascending
                ? order == .orderedAscending
                : order == .orderedDescending
        }
    }

    private func compare(
        _ lhs: LibraryTrackProjection,
        _ rhs: LibraryTrackProjection
    ) -> ComparisonResult {
        switch field {
        case .song:
            lhs.title.localizedStandardCompare(rhs.title)
        case .album:
            lhs.album.localizedStandardCompare(rhs.album)
        case .year:
            compare(lhs.year ?? 0, rhs.year ?? 0)
        case .dateAdded:
            lhs.dateAdded.compare(rhs.dateAdded)
        case .playCount:
            compare(lhs.playCount, rhs.playCount)
        case .time:
            compare(lhs.duration, rhs.duration)
        }
    }

    private func compare<T: Comparable>(
        _ lhs: T,
        _ rhs: T
    ) -> ComparisonResult {
        if lhs == rhs {
            return .orderedSame
        }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }
}

struct TrackTableWidthRange {
    let minimum: Double
    let defaultValue: Double
    let maximum: Double
}

enum TrackTableWidth {
    static let song = TrackTableWidthRange(
        minimum: 220.0,
        defaultValue: 360.0,
        maximum: 720.0
    )
    static let album = TrackTableWidthRange(
        minimum: 130.0,
        defaultValue: 220.0,
        maximum: 520.0
    )
    static let year = TrackTableWidthRange(
        minimum: 54.0,
        defaultValue: 72.0,
        maximum: 120.0
    )
    static let dateAdded = TrackTableWidthRange(
        minimum: 90.0,
        defaultValue: 120.0,
        maximum: 220.0
    )
    static let playCount = TrackTableWidthRange(
        minimum: 54.0,
        defaultValue: 76.0,
        maximum: 140.0
    )
    static let time = TrackTableWidthRange(
        minimum: 54.0,
        defaultValue: 72.0,
        maximum: 120.0
    )
}

struct TrackTableHeaderCell: View {
    let title: String
    let alignment: Alignment
    let isSorted: Bool
    let direction: TrackTableSortDirection
    let minimumWidth: Double
    let maximumWidth: Double
    @Binding var width: Double
    let sortAction: () -> Void

    @State private var dragStartWidth: Double?
    @State private var isResizerHovered = false

    var body: some View {
        Button(action: sortAction) {
            HStack(spacing: 5) {
                if alignment == .trailing {
                    Spacer(minLength: 0)
                }
                Text(title)
                    .lineLimit(1)
                if isSorted {
                    Image(
                        systemName: direction == .ascending
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(.system(size: 8, weight: .bold))
                }
                if alignment != .trailing {
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: CGFloat(width), alignment: alignment)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.clear)
                .frame(width: 9)
                .contentShape(Rectangle())
                .overlay {
                    Rectangle()
                        .fill(
                            isResizerHovered || dragStartWidth != nil
                                ? CadenceTheme.strongSeparator
                                : CadenceTheme.separator
                        )
                        .frame(width: 1)
                }
                .gesture(
                    DragGesture(
                        minimumDistance: 1,
                        coordinateSpace: .global
                    )
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        let start = dragStartWidth ?? width
                        width = min(
                            max(
                                start + Double(value.translation.width),
                                minimumWidth
                            ),
                            maximumWidth
                        )
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
                )
                .onHover { isInside in
                    if isInside, !isResizerHovered {
                        NSCursor.resizeLeftRight.push()
                    } else if !isInside, isResizerHovered {
                        NSCursor.pop()
                    }
                    isResizerHovered = isInside
                }
                .onDisappear {
                    if isResizerHovered {
                        NSCursor.pop()
                        isResizerHovered = false
                    }
                }
        }
        .accessibilityValue(
            isSorted
                ? direction == .ascending ? "Ascending" : "Descending"
                : "Not sorted"
        )
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 16.0 : -16.0
            width = min(max(width + delta, minimumWidth), maximumWidth)
        }
    }
}
