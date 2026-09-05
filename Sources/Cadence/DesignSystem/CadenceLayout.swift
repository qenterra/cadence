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
    static let minimumCardWidth: CGFloat = 164
    static let maximumCardWidth: CGFloat = 196
    static let cardWidth = minimumCardWidth

    static func widthRange(
        for size: CatalogCardSize
    ) -> ClosedRange<CGFloat> {
        switch size {
        case .automatic:
            164 ... 196
        case .small:
            136 ... 156
        case .medium:
            184 ... 220
        case .large:
            224 ... 272
        }
    }

    static func columns(
        availableWidth: CGFloat,
        spacing: CGFloat
    ) -> [GridItem] {
        let resolvedWidth = max(availableWidth, minimumCardWidth)
        let count = max(
            Int(
                (resolvedWidth + spacing)
                    / (minimumCardWidth + spacing)
            ),
            1
        )
        let distributedWidth = min(
            max(
                (
                    resolvedWidth
                        - CGFloat(max(count - 1, 0)) * spacing
                ) / CGFloat(count),
                minimumCardWidth
            ),
            maximumCardWidth
        )
        return Array(
            repeating: GridItem(
                .fixed(distributedWidth),
                spacing: spacing,
                alignment: .top
            ),
            count: count
        )
    }

    /// SwiftUI chooses the count, then distributes useful width across cards.
    static func layoutColumns(spacing: CGFloat) -> [GridItem] {
        layoutColumns(spacing: spacing, size: .automatic)
    }

    static func layoutColumns(
        spacing: CGFloat,
        size: CatalogCardSize
    ) -> [GridItem] {
        let range = widthRange(for: size)
        return [
            GridItem(
                .adaptive(
                    minimum: range.lowerBound,
                    maximum: range.upperBound
                ),
                spacing: spacing,
                alignment: .top
            ),
        ]
    }
}

extension EnvironmentValues {
    @Entry var catalogCardSize: CatalogCardSize = .automatic
}
