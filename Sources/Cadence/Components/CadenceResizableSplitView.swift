import AppKit
import SwiftUI

enum CadenceFixedSplitPane {
    case leading
    case trailing
}

struct CadenceResizableSplitView<Leading: View, Trailing: View>: View {
    let fixedPane: CadenceFixedSplitPane
    @Binding var fixedWidth: Double
    let fixedMinimum: CGFloat
    let fixedMaximum: CGFloat
    let flexibleMinimum: CGFloat
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @State private var dragStartWidth: Double?
    @State private var isDividerHovered = false

    var body: some View {
        GeometryReader { geometry in
            let dividerWidth = CGFloat(7)
            let availableWidth = max(geometry.size.width - dividerWidth, 0)
            let resolvedWidth = resolvedFixedWidth(
                availableWidth: availableWidth
            )
            let flexibleWidth = max(
                availableWidth - resolvedWidth,
                0
            )

            HStack(spacing: 0) {
                if fixedPane == .leading {
                    leading
                        .frame(width: resolvedWidth)
                    divider(availableWidth: availableWidth)
                    trailing
                        .frame(width: flexibleWidth)
                } else {
                    leading
                        .frame(width: flexibleWidth)
                    divider(availableWidth: availableWidth)
                    trailing
                        .frame(width: resolvedWidth)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
        }
    }

    private func divider(
        availableWidth: CGFloat
    ) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 7)
            .overlay {
                Rectangle()
                    .fill(
                        isDividerHovered
                            ? CadenceTheme.strongSeparator
                            : CadenceTheme.separator
                    )
                    .frame(width: isDividerHovered ? 2 : 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = fixedWidth
                        }
                        let start = dragStartWidth ?? fixedWidth
                        let delta = Double(value.translation.width)
                        let proposed = fixedPane == .leading
                            ? start + delta
                            : start - delta
                        fixedWidth = Double(
                            clamped(
                                CGFloat(proposed),
                                availableWidth: availableWidth
                            )
                        )
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .onHover { isInside in
                if isInside, !isDividerHovered {
                    NSCursor.resizeLeftRight.push()
                } else if !isInside, isDividerHovered {
                    NSCursor.pop()
                }
                isDividerHovered = isInside
            }
            .accessibilityElement()
            .accessibilityLabel("Resize Columns")
            .accessibilityValue(
                Int(resolvedFixedWidth(availableWidth: availableWidth))
                    .formatted()
            )
    }

    private func resolvedFixedWidth(
        availableWidth: CGFloat
    ) -> CGFloat {
        clamped(
            CGFloat(fixedWidth),
            availableWidth: availableWidth
        )
    }

    private func clamped(
        _ proposedWidth: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        let maximum = min(
            fixedMaximum,
            max(availableWidth - flexibleMinimum, fixedMinimum)
        )
        return min(max(proposedWidth, fixedMinimum), maximum)
    }
}
