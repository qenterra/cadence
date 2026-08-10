import Foundation

enum TrackTableLayoutMode: Equatable, Sendable {
    case full
    case compact
}

enum TrackTableColumnPolicy {
    static let compactThreshold = 720.0

    static func rowChromeWidth(
        columnCount: Int
    ) -> Double {
        let horizontalPadding = 24.0
        let actionWidth = 28.0
        let spacing = Double(max(columnCount, 0) + 2) * 14.0
        return horizontalPadding + actionWidth + spacing
    }

    static func contentWidth(
        availableWidth: Double,
        columns: [TrackTableColumn]
    ) -> Double {
        max(
            availableWidth - rowChromeWidth(columnCount: columns.count),
            1
        )
    }

    static func mode(
        availableWidth: Double
    ) -> TrackTableLayoutMode {
        availableWidth < compactThreshold ? .compact : .full
    }

    static func layout(
        availableWidth: Double,
        columns: [TrackTableColumn],
        preferred: TrackTableResolvedWidths?
    ) -> TrackTableResolvedWidths {
        let available = max(availableWidth, 1)
        let preferred = preferred ?? defaultWidths
        let active = [Column.song] + columns.map(Column.init)
        let minimumTotal = active.reduce(0) { $0 + $1.minimum }
        let preferredTotal = active.reduce(0) {
            $0 + $1.value(in: preferred)
        }

        var values: [Column: Double] = [:]
        if available < minimumTotal {
            let scale = available / minimumTotal
            for column in active {
                values[column] = column.minimum * scale
            }
        } else if available < preferredTotal {
            let flexibleTotal = preferredTotal - minimumTotal
            let remaining = available - minimumTotal
            for column in active {
                let flexible = column.value(in: preferred) - column.minimum
                values[column] = column.minimum
                    + remaining * flexible / max(flexibleTotal, 1)
            }
        } else {
            let extra = available - preferredTotal
            let weightTotal = active.reduce(0) {
                $0 + $1.expansionWeight
            }
            for column in active {
                values[column] = column.value(in: preferred)
                    + extra * column.expansionWeight / weightTotal
            }
        }

        let resolved = TrackTableResolvedWidths(
            song: values[.song] ?? 0,
            album: values[.album] ?? 0,
            year: values[.year] ?? 0,
            time: values[.time] ?? 0
        )
        let actual = resolved.song + columns.reduce(0) {
            $0 + resolved[$1]
        }
        return TrackTableResolvedWidths(
            song: resolved.song + available - actual,
            album: resolved.album,
            year: resolved.year,
            time: resolved.time
        )
    }

    static let defaultWidths = TrackTableResolvedWidths(
        song: TrackTableWidth.song.defaultValue,
        album: TrackTableWidth.album.defaultValue,
        year: TrackTableWidth.year.defaultValue,
        time: TrackTableWidth.time.defaultValue
    )
}

private extension TrackTableColumnPolicy {
    enum Column: Hashable {
        case song
        case album
        case year
        case time

        init(_ column: TrackTableColumn) {
            self = switch column {
            case .album: .album
            case .year: .year
            case .time: .time
            }
        }

        var minimum: Double {
            switch self {
            case .song: TrackTableWidth.song.minimum
            case .album: TrackTableWidth.album.minimum
            case .year: TrackTableWidth.year.minimum
            case .time: TrackTableWidth.time.minimum
            }
        }

        var expansionWeight: Double {
            switch self {
            case .song: 3
            case .album: 2
            case .year, .time: 0.5
            }
        }

        func value(
            in widths: TrackTableResolvedWidths
        ) -> Double {
            switch self {
            case .song: widths.song
            case .album: widths.album
            case .year: widths.year
            case .time: widths.time
            }
        }
    }
}
