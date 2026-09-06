import AppKit
import QenTerraComponents
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
        let resolution = ResizableSplitLayout.resolve(
            availableWidth: Double(totalWidth),
            proposedFixedWidth: Double(proposedFixedWidth),
            fixedPane: .leading,
            minimumFixedWidth: Double(fixedMinimum),
            maximumFixedWidth: Double(fixedMaximum),
            minimumFlexibleWidth: Double(flexibleMinimum),
            separatorWidth: Double(dividerWidth)
        )
        self.dividerWidth = resolution.separatorWidth
        fixedWidth = resolution.leadingWidth
        flexibleWidth = resolution.trailingWidth
    }

    private init(
        dividerWidth: CGFloat,
        fixedWidth: CGFloat,
        flexibleWidth: CGFloat
    ) {
        self.dividerWidth = dividerWidth
        self.fixedWidth = fixedWidth
        self.flexibleWidth = flexibleWidth
    }

    static func resolve(
        totalWidth: CGFloat,
        proposedFixedWidth: CGFloat,
        fixedPane: CadenceFixedSplitPane,
        fixedMinimum: CGFloat,
        fixedMaximum: CGFloat,
        flexibleMinimum: CGFloat
    ) -> Self {
        let resolution = ResizableSplitLayout.resolve(
            availableWidth: Double(totalWidth),
            proposedFixedWidth: Double(proposedFixedWidth),
            fixedPane: fixedPane == .leading ? .leading : .trailing,
            minimumFixedWidth: Double(fixedMinimum),
            maximumFixedWidth: Double(fixedMaximum),
            minimumFlexibleWidth: Double(flexibleMinimum),
            separatorWidth: Double(standardDividerWidth)
        )
        return Self(
            dividerWidth: resolution.separatorWidth,
            fixedWidth: fixedPane == .leading
                ? resolution.leadingWidth
                : resolution.trailingWidth,
            flexibleWidth: fixedPane == .leading
                ? resolution.trailingWidth
                : resolution.leadingWidth
        )
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
            let layout = CadenceSplitLayout.resolve(
                totalWidth: geometry.size.width,
                proposedFixedWidth: CGFloat(liveWidth ?? fixedWidth),
                fixedPane: fixedPane,
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
                CadenceSplitLayout.resolve(
                    totalWidth: totalWidth,
                    proposedFixedWidth: CGFloat(proposed),
                    fixedPane: fixedPane,
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
        CadenceSplitLayout.resolve(
            totalWidth: totalWidth,
            proposedFixedWidth: CGFloat(liveWidth ?? fixedWidth),
            fixedPane: fixedPane,
            fixedMinimum: fixedMinimum,
            fixedMaximum: fixedMaximum,
            flexibleMinimum: flexibleMinimum
        ).fixedWidth
    }
}
