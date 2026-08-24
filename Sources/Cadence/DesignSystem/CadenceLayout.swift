import SwiftUI

/// Product-level layout roles built from a four-point spacing scale.
///
/// Features consume semantic roles instead of choosing raw values. Geometry
/// that belongs to one feature stays in that feature's named metrics type.
enum CadenceLayout {
    static let textStack: CGFloat = 4
    static let compactGap: CGFloat = 8
    static let controlGap: CGFloat = 12
    static let contentGap: CGFloat = 16
    static let panelInset: CGFloat = 20
    static let pageInset: CGFloat = 24
    static let sectionGap: CGFloat = 32

    static let rowHeight: CGFloat = 48
    static let readableContentWidth: CGFloat = 760
}

enum CatalogCardLayoutMetrics {
    static let cardWidth: CGFloat = 196

    static func columns(
        availableWidth: CGFloat,
        spacing: CGFloat
    ) -> [GridItem] {
        let resolvedWidth = max(availableWidth, cardWidth)
        let count = max(
            Int((resolvedWidth + spacing) / (cardWidth + spacing)),
            1
        )
        return Array(
            repeating: GridItem(
                .fixed(cardWidth),
                spacing: spacing,
                alignment: .top
            ),
            count: count
        )
    }

    /// SwiftUI performs the column-count calculation while both bounds keep
    /// every rendered card at the exact shared catalog width.
    static func layoutColumns(spacing: CGFloat) -> [GridItem] {
        [
            GridItem(
                .adaptive(minimum: cardWidth, maximum: cardWidth),
                spacing: spacing,
                alignment: .top
            ),
        ]
    }
}
