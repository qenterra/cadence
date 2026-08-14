import SwiftUI

struct NavigationRail: View {
    @Binding var selection: NavigationDestination

    var suppressesSelection = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedDestination: NavigationDestination?
    @State private var hoveredDestination: NavigationDestination?
    @AppStorage("navigationRail.expanded")
    private var isExpanded = NavigationRailConfiguration.defaultIsExpanded
    @AppStorage("navigationRail.order")
    private var orderRawValue = NavigationRailConfiguration.defaultOrderRawValue
    @AppStorage("navigationRail.hidden")
    private var hiddenRawValue = ""

    var body: some View {
        VStack(spacing: 8) {
            primaryNavigation

            Spacer(minLength: 12)

            Divider()
                .padding(.horizontal, NavigationRailMetrics.rowInset)

            railButton(.trash)
        }
        .frame(
            width: NavigationRailMetrics.contentWidth(
                isExpanded: isExpanded
            ),
            alignment: .leading
        )
        .padding(.horizontal, NavigationRailMetrics.horizontalInset)
        .padding(.vertical, NavigationRailMetrics.verticalInset)
        .frame(
            width: NavigationRailMetrics.totalWidth(
                isExpanded: isExpanded
            ),
            alignment: .leading
        )
        .clipped()
        .background(.thinMaterial)
    }

    private var primaryNavigation: some View {
        VStack(spacing: 0) {
            expansionButton
                .padding(.bottom, 12)

            ForEach(primarySections) { section in
                navigationSection(section)
            }
        }
    }

    private var primarySections: [NavigationRailSection] {
        NavigationRailConfiguration.visibleSections(
            orderRawValue: orderRawValue,
            hiddenRawValue: hiddenRawValue
        )
    }

    private func navigationSection(
        _ section: NavigationRailSection
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if isExpanded {
                Text(section.group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, NavigationRailMetrics.rowInset)
                    .frame(height: NavigationRailMetrics.sectionHeaderHeight)
                    .accessibilityAddTraits(.isHeader)
            }

            ForEach(section.destinations) { destination in
                railButton(destination)
            }
        }
        .padding(.bottom, NavigationRailMetrics.sectionSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(section.group.title)
    }

    private var expansionButton: some View {
        Button {
            if reduceMotion {
                isExpanded.toggle()
            } else {
                withAnimation(.smooth(duration: CadenceTheme.motionReplace)) {
                    isExpanded.toggle()
                }
            }
        } label: {
            railLabel(
                systemName: isExpanded ? "sidebar.left" : "sidebar.right",
                title: "Collapse",
                animatesSymbolReplacement: true
            )
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(CadenceRowButtonStyle())
        .help(isExpanded ? "Collapse Sidebar" : "Expand Sidebar")
        .accessibilityLabel(
            isExpanded ? "Collapse Sidebar" : "Expand Sidebar"
        )
    }

    private func railButton(_ destination: NavigationDestination) -> some View {
        let isSelected = !suppressesSelection && selection == destination

        return Button {
            selection = destination
        } label: {
            railLabel(
                systemName: destination.symbolName,
                title: destination.title
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background {
                BrowserRowSurface(
                    isSelected: isSelected,
                    isHovered: hoveredDestination == destination,
                    isFocused: focusedDestination == destination
                )
            }
        }
        .buttonStyle(CadenceRowButtonStyle())
        .focused($focusedDestination, equals: destination)
        .onHover { isInside in
            hoveredDestination = isInside ? destination : nil
        }
        .help(destination.title)
        .accessibilityLabel(destination.title)
        .accessibilityHint(destination.accessibilityDescription)
        .accessibilityValue(isSelected ? "Selected" : "")
        .frame(
            width: NavigationRailMetrics.contentWidth(
                isExpanded: isExpanded
            ),
            alignment: .center
        )
    }

    private func railLabel(
        systemName: String,
        title: String,
        animatesSymbolReplacement: Bool = false
    ) -> some View {
        Group {
            if isExpanded {
                HStack(spacing: 12) {
                    railIcon(
                        systemName,
                        animatesSymbolReplacement: animatesSymbolReplacement
                    )
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, NavigationRailMetrics.rowInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                railIcon(
                    systemName,
                    animatesSymbolReplacement: animatesSymbolReplacement
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(
            width: NavigationRailMetrics.rowWidth(isExpanded: isExpanded),
            height: NavigationRailMetrics.rowHeight
        )
        .clipped()
    }

    private func railIcon(
        _ systemName: String,
        animatesSymbolReplacement: Bool
    ) -> some View {
        Group {
            if animatesSymbolReplacement {
                Image(systemName: systemName)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemName: systemName)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .symbolRenderingMode(.hierarchical)
        .frame(
            width: NavigationRailMetrics.iconSlotWidth,
            height: NavigationRailMetrics.rowHeight
        )
    }
}

enum NavigationRailMetrics {
    static let collapsedWidth: CGFloat = 72
    static let expandedWidth: CGFloat = 220
    static let horizontalInset: CGFloat = 10
    static let verticalInset: CGFloat = 14
    static let rowInset: CGFloat = 10
    static let rowHeight: CGFloat = 42
    static let iconSlotWidth: CGFloat = 32
    static let sectionHeaderHeight: CGFloat = 20
    static let sectionSpacing: CGFloat = 12

    static func totalWidth(isExpanded: Bool) -> CGFloat {
        isExpanded ? expandedWidth : collapsedWidth
    }

    static func contentWidth(isExpanded: Bool) -> CGFloat {
        totalWidth(isExpanded: isExpanded) - horizontalInset * 2
    }

    static func rowWidth(isExpanded: Bool) -> CGFloat {
        isExpanded ? contentWidth(isExpanded: true) : rowHeight
    }

    static func iconCenterX(isExpanded: Bool) -> CGFloat {
        if isExpanded {
            return horizontalInset + rowInset + iconSlotWidth / 2
        }
        let centeredRowInset = (
            contentWidth(isExpanded: false) - rowWidth(isExpanded: false)
        ) / 2
        return horizontalInset + centeredRowInset + rowHeight / 2
    }
}
