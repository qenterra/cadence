import SwiftUI

struct CadenceFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(
        horizontalSpacing: CGFloat = 8,
        verticalSpacing: CGFloat = 8
    ) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        layout(
            width: proposal.width ?? .greatestFiniteMagnitude,
            subviews: subviews
        ).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let result = layout(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + origin.x,
                    y: bounds.minY + origin.y
                ),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func layout(
        width: CGFloat,
        subviews: Subviews
    ) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var cursor = CGPoint.zero
        var rowHeight = CGFloat.zero
        var usedWidth = CGFloat.zero

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > width {
                cursor.x = 0
                cursor.y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            origins.append(cursor)
            usedWidth = max(usedWidth, cursor.x + size.width)
            rowHeight = max(rowHeight, size.height)
            cursor.x += size.width + horizontalSpacing
        }

        return (
            CGSize(
                width: min(usedWidth, width),
                height: cursor.y + rowHeight
            ),
            origins
        )
    }
}
