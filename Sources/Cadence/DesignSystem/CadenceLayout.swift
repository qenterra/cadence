import CoreGraphics
import QenTerraDesignTokens

/// Product-level layout roles built from the QDS four-point spacing scale.
///
/// Features consume semantic roles instead of choosing raw values. Geometry
/// that belongs to one feature stays in that feature's named metrics type.
enum CadenceLayout {
    static let textStack = CGFloat(QDS.Space.value1)
    static let compactGap = CGFloat(QDS.Space.value2)
    static let controlGap = CGFloat(QDS.Space.value3)
    static let contentGap = CGFloat(QDS.Space.value4)
    static let panelInset = CGFloat(QDS.Space.value5)
    static let pageInset = CGFloat(QDS.Space.value6)
    static let sectionGap = CGFloat(QDS.Space.value8)

    static let rowHeight = CGFloat(QDS.Size.rowStandard)
    static let comfortableRowHeight = CGFloat(QDS.Size.rowComfortable)
    static let readableContentWidth = CGFloat(QDS.Size.contentReadable)
}
