import AppKit
import SwiftUI

enum CadenceFixedSplitPane {
    case leading
    case trailing
}

struct CadenceSplitLayout: Equatable, Sendable {
    static let standardDividerWidth = CGFloat(7)

    let dividerWidth: CGFloat
    let fixedWidth: CGFloat
    let flexibleWidth: CGFloat

    init(
        totalWidth: CGFloat,
        proposedFixedWidth: CGFloat,
        fixedMinimum: CGFloat,
        fixedMaximum: CGFloat,
        flexibleMinimum: CGFloat,
        dividerWidth: CGFloat = standardDividerWidth
    ) {
        self.dividerWidth = dividerWidth
        let availableWidth = max(totalWidth - dividerWidth, 0)
        let minimum = min(fixedMinimum, availableWidth)
        let maximum = min(
            fixedMaximum,
            max(availableWidth - flexibleMinimum, minimum),
            availableWidth
        )
        fixedWidth = min(max(proposedFixedWidth, minimum), maximum)
        flexibleWidth = max(availableWidth - fixedWidth, 0)
    }
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
    @State private var liveWidth: Double?
    @State private var isDividerHovered = false

    var body: some View {
        GeometryReader { geometry in
            let layout = CadenceSplitLayout(
                totalWidth: geometry.size.width,
                proposedFixedWidth: CGFloat(liveWidth ?? fixedWidth),
                fixedMinimum: fixedMinimum,
                fixedMaximum: fixedMaximum,
                flexibleMinimum: flexibleMinimum
            )

            HStack(alignment: .top, spacing: 0) {
                if fixedPane == .leading {
                    leading
                        .frame(width: layout.fixedWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                    divider(totalWidth: geometry.size.width)
                    trailing
                        .frame(width: layout.flexibleWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    leading
                        .frame(width: layout.flexibleWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                    divider(totalWidth: geometry.size.width)
                    trailing
                        .frame(width: layout.fixedWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
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
        totalWidth: CGFloat
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
            .gesture(resizeGesture(totalWidth: totalWidth))
            .onHover { isInside in
                if isInside, !isDividerHovered {
                    NSCursor.resizeLeftRight.push()
                } else if !isInside, isDividerHovered {
                    NSCursor.pop()
                }
                isDividerHovered = isInside
            }
            .onDisappear {
                if isDividerHovered {
                    NSCursor.pop()
                    isDividerHovered = false
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Resize Columns")
            .accessibilityValue(
                Int(resolvedFixedWidth(totalWidth: totalWidth))
                    .formatted()
            )
    }

    private func resizeGesture(
        totalWidth: CGFloat
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 1,
            coordinateSpace: .global
        )
        .onChanged { value in
            if dragStartWidth == nil {
                dragStartWidth = fixedWidth
            }
            let start = dragStartWidth ?? fixedWidth
            let delta = Double(value.translation.width)
            let proposed = fixedPane == .leading
                ? start + delta
                : start - delta
            liveWidth = Double(
                CadenceSplitLayout(
                    totalWidth: totalWidth,
                    proposedFixedWidth: CGFloat(proposed),
                    fixedMinimum: fixedMinimum,
                    fixedMaximum: fixedMaximum,
                    flexibleMinimum: flexibleMinimum
                ).fixedWidth
            )
        }
        .onEnded { _ in
            if let liveWidth {
                fixedWidth = liveWidth
            }
            liveWidth = nil
            dragStartWidth = nil
        }
    }

    private func resolvedFixedWidth(
        totalWidth: CGFloat
    ) -> CGFloat {
        CadenceSplitLayout(
            totalWidth: totalWidth,
            proposedFixedWidth: CGFloat(liveWidth ?? fixedWidth),
            fixedMinimum: fixedMinimum,
            fixedMaximum: fixedMaximum,
            flexibleMinimum: flexibleMinimum
        ).fixedWidth
    }
}
