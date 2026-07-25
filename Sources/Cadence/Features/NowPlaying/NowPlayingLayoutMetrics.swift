import CoreGraphics

struct NowPlayingLayoutMetrics: Hashable, Sendable {
    static let minimumContextWidth: CGFloat = 340
    static let maximumContextWidth: CGFloat = 560
    static let minimumPanelWidth: CGFloat = 520
    static let artworkRange: ClosedRange<CGFloat> = 220 ... 360

    let contextWidth: CGFloat
    let panelWidth: CGFloat
    let artworkSize: CGFloat

    init(totalWidth: CGFloat) {
        let resolvedWidth = max(
            totalWidth,
            Self.minimumContextWidth + Self.minimumPanelWidth + 1
        )
        let maximumAllowedContext = max(
            resolvedWidth - Self.minimumPanelWidth - 1,
            Self.minimumContextWidth
        )
        contextWidth = min(
            max(resolvedWidth * 0.4, Self.minimumContextWidth),
            min(Self.maximumContextWidth, maximumAllowedContext)
        )
        panelWidth = resolvedWidth - contextWidth - 1
        artworkSize = min(
            max(contextWidth - 88, Self.artworkRange.lowerBound),
            Self.artworkRange.upperBound
        )
    }
}
