import Foundation

enum TrackTableLayoutMode: Equatable, Sendable {
    case full
    case compact
}

enum TrackTableColumnPolicy {
    static let horizontalInset = CadenceLayout.pageInset
    static let selectionHorizontalInset = CadenceLayout.compactGap
    static let columnSpacing = CadenceLayout.controlGap
    static let actionWidth: CGFloat = 28
    static let favoriteControlWidth = CatalogTileFavoriteLayout.controlSize
    static let songContentSpacing = CadenceLayout.compactGap
    static let minimumSongWidth = 360.0
    static let albumWidth = 190.0
    static let yearWidth = 64.0
    static let timeWidth = 64.0
    static let compactThreshold = minimumSongWidth
        + albumWidth
        + yearWidth
        + timeWidth
        + rowChromeWidth(columnCount: TrackTableColumn.allCases.count)

    static func rowChromeWidth(
        columnCount: Int
    ) -> Double {
        let horizontalPadding = Double(horizontalInset * 2)
        let spacing = Double(max(columnCount, 0) + 2)
            * Double(columnSpacing)
        return horizontalPadding + Double(actionWidth) + spacing
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
        columns: [TrackTableColumn]
    ) -> TrackTableResolvedWidths {
        let available = max(availableWidth, 1)
        let secondaryWidth = columns.reduce(0.0) { partial, column in
            partial + fixedWidth(for: column)
        }
        return TrackTableResolvedWidths(
            song: max(available - secondaryWidth, 1),
            album: columns.contains(.album) ? albumWidth : 0,
            year: columns.contains(.year) ? yearWidth : 0,
            time: columns.contains(.time) ? timeWidth : 0
        )
    }

    static let defaultWidths = TrackTableResolvedWidths(
        song: minimumSongWidth,
        album: albumWidth,
        year: yearWidth,
        time: timeWidth
    )

    private static func fixedWidth(
        for column: TrackTableColumn
    ) -> Double {
        switch column {
        case .album:
            albumWidth
        case .year:
            yearWidth
        case .time:
            timeWidth
        }
    }
}
