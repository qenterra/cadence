import QenTerraDesignTokens
import SwiftUI

/// Product-level layout roles built from a four-point spacing scale.
///
/// Features consume semantic roles instead of choosing raw values. Geometry
/// that belongs to one feature stays in that feature's named metrics type.
enum CadenceLayout {
    private static let metrics = DesignProductMetrics.cadence

    static let textStack = CGFloat(metrics.textStack)
    static let compactGap = CGFloat(metrics.compactGap)
    static let controlGap = CGFloat(metrics.controlGap)
    static let contentGap = CGFloat(metrics.contentGap)
    static let panelInset = CGFloat(metrics.panelInset)
    static let pageInset = CGFloat(metrics.pageInset)
    static let sectionGap = CGFloat(metrics.sectionGap)

    static let rowHeight = CGFloat(metrics.rowHeight)
    static let readableContentWidth = CGFloat(metrics.readableContentWidth)
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
