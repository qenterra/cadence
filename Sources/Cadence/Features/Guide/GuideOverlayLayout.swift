import CoreGraphics

enum GuideOverlayLayout {
    static let cardSize = CGSize(width: 370, height: 320)
    static let margin = CGFloat(22)
    static let spacing = CGFloat(18)
    static let spotlightMargin = CGFloat(12)
    static let spotlightPadding = CGFloat(14)

    static func spotlightRect(
        rawRect: CGRect,
        viewportSize: CGSize
    ) -> CGRect? {
        guard
            rawRect.width > 0,
            rawRect.height > 0,
            viewportSize.width > spotlightMargin * 2,
            viewportSize.height > spotlightMargin * 2
        else {
            return nil
        }

        let safeBounds = CGRect(origin: .zero, size: viewportSize)
            .insetBy(dx: spotlightMargin, dy: spotlightMargin)
        let desired = rawRect.insetBy(
            dx: -spotlightPadding / 2,
            dy: -spotlightPadding / 2
        )
        let size = CGSize(
            width: min(desired.width, safeBounds.width),
            height: min(desired.height, safeBounds.height)
        )
        let origin = CGPoint(
            x: desired.minX.clamped(
                to: safeBounds.minX ... safeBounds.maxX - size.width
            ),
            y: desired.minY.clamped(
                to: safeBounds.minY ... safeBounds.maxY - size.height
            )
        )
        return CGRect(origin: origin, size: size)
    }

    static func cardFrame(
        viewportSize: CGSize,
        target: CGRect?,
        placement: GuideCardPlacement
    ) -> CGRect {
        guard let target else {
            return centeredCardFrame(in: viewportSize)
        }

        let resolvedPlacement = placement == .automatic
            ? automaticPlacement(in: viewportSize, target: target)
            : placement
        let center = initialCardCenter(
            placement: resolvedPlacement,
            viewportSize: viewportSize,
            target: target
        )
        return clampedCardFrame(center: center, viewportSize: viewportSize)
    }

    static func cardCenter(
        viewportSize: CGSize,
        target: CGRect?,
        placement: GuideCardPlacement
    ) -> CGPoint {
        let frame = cardFrame(
            viewportSize: viewportSize,
            target: target,
            placement: placement
        )
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private static func automaticPlacement(
        in viewportSize: CGSize,
        target: CGRect
    ) -> GuideCardPlacement {
        let candidates = [
            PlacementCandidate(
                placement: .above,
                score: (target.minY - margin - spacing) / cardSize.height
            ),
            PlacementCandidate(
                placement: .below,
                score: (
                    viewportSize.height - margin - spacing - target.maxY
                ) / cardSize.height
            ),
            PlacementCandidate(
                placement: .leading,
                score: (target.minX - margin - spacing) / cardSize.width
            ),
            PlacementCandidate(
                placement: .trailing,
                score: (
                    viewportSize.width - margin - spacing - target.maxX
                ) / cardSize.width
            ),
        ]
        return candidates.max { $0.score < $1.score }?.placement ?? .center
    }

    private static func initialCardCenter(
        placement: GuideCardPlacement,
        viewportSize: CGSize,
        target: CGRect
    ) -> CGPoint {
        switch placement {
        case .automatic, .center:
            CGPoint(
                x: viewportSize.width / 2,
                y: viewportSize.height / 2
            )
        case .above:
            CGPoint(
                x: target.midX,
                y: target.minY - spacing - cardSize.height / 2
            )
        case .below:
            CGPoint(
                x: target.midX,
                y: target.maxY + spacing + cardSize.height / 2
            )
        case .leading:
            CGPoint(
                x: target.minX - spacing - cardSize.width / 2,
                y: target.midY
            )
        case .trailing:
            CGPoint(
                x: target.maxX + spacing + cardSize.width / 2,
                y: target.midY
            )
        }
    }

    private static func clampedCardFrame(
        center: CGPoint,
        viewportSize: CGSize
    ) -> CGRect {
        let safeBounds = CGRect(origin: .zero, size: viewportSize)
            .insetBy(dx: margin, dy: margin)
        let size = CGSize(
            width: min(cardSize.width, safeBounds.width),
            height: min(cardSize.height, safeBounds.height)
        )
        let origin = CGPoint(
            x: (center.x - size.width / 2).clamped(
                to: safeBounds.minX ... safeBounds.maxX - size.width
            ),
            y: (center.y - size.height / 2).clamped(
                to: safeBounds.minY ... safeBounds.maxY - size.height
            )
        )
        return CGRect(origin: origin, size: size)
    }

    private static func centeredCardFrame(in viewportSize: CGSize) -> CGRect {
        clampedCardFrame(
            center: CGPoint(
                x: viewportSize.width / 2,
                y: viewportSize.height / 2
            ),
            viewportSize: viewportSize
        )
    }
}

private struct PlacementCandidate {
    let placement: GuideCardPlacement
    let score: CGFloat
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
