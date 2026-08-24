import Foundation
import SwiftUI

enum TrackTableSortField: String, CaseIterable, Codable, Sendable {
    case song
    case album
    case year
    case time

    var title: String {
        switch self {
        case .song: String(localized: "Track")
        case .album: String(localized: "Album")
        case .year: String(localized: "Year")
        case .time: String(localized: "Time")
        }
    }
}

enum TrackTableSortDirection: String, Codable, Sendable {
    case ascending
    case descending

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

struct TrackTableSortDescriptor: Equatable, Hashable, Sendable {
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

struct TrackTableHeaderCell: View {
    let title: String
    let alignment: Alignment
    let isSorted: Bool
    let direction: TrackTableSortDirection
    let resolvedWidth: Double
    let sortAction: () -> Void

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
        .frame(width: CGFloat(resolvedWidth), alignment: alignment)
        .accessibilityValue(
            isSorted
                ? direction == .ascending ? "Ascending" : "Descending"
                : "Not sorted"
        )
    }
}
