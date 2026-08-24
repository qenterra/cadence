import SwiftUI

struct NavigationRailAccessibilityItem: Equatable, Sendable {
    let label: String
    let hint: String
    let value: String
}

enum NavigationRailAccessibilityContract {
    static func items(
        sections: [NavigationRailSection],
        isExpanded: Bool,
        selected: NavigationDestination
    ) -> [NavigationRailAccessibilityItem] {
        let expansion = NavigationRailAccessibilityItem(
            label: isExpanded
                ? String(localized: "Collapse Sidebar")
                : String(localized: "Expand Sidebar"),
            hint: isExpanded
                ? String(localized: "Shows navigation as icons only")
                : String(localized: "Shows navigation icons and labels"),
            value: ""
        )
        let destinations = sections
            .flatMap(\.destinations)
            .map { item(for: $0, selected: selected) }
        return [expansion] + destinations + [item(for: .trash, selected: selected)]
    }

    static func item(
        for destination: NavigationDestination,
        selected: NavigationDestination?
    ) -> NavigationRailAccessibilityItem {
        NavigationRailAccessibilityItem(
            label: destination.title,
            hint: destination.accessibilityDescription,
            value: selected == destination
                ? String(localized: "Selected")
                : ""
        )
    }
}

struct NavigationRail: View {
    @Binding var selection: NavigationDestination

    var suppressesSelection = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedDestination: NavigationDestination?
    @State private var hoveredDestination: NavigationDestination?
    @State private var activationCounts: [NavigationDestination: Int] = [:]
    @AppStorage("navigationRail.expanded")
    private var isExpanded = NavigationRailConfiguration.defaultIsExpanded
    @AppStorage("navigationRail.order")
    private var orderRawValue = NavigationRailConfiguration.defaultOrderRawValue
    @AppStorage("navigationRail.hidden")
    private var hiddenRawValue = ""

    var body: some View {
        VStack(spacing: NavigationRailMetrics.rowSpacing) {
            primaryNavigation

            Spacer(minLength: CadenceLayout.controlGap)

            ForEach(bottomDestinations) { destination in
                railButton(destination)
            }
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
        VStack(spacing: NavigationRailMetrics.rowSpacing) {
            expansionButton
                .padding(.bottom, CadenceLayout.controlGap)

            ForEach(primaryDestinations) { destination in
                railButton(destination)
            }
        }
    }

    private var primarySections: [NavigationRailSection] {
        NavigationRailConfiguration.visibleSections(
            orderRawValue: orderRawValue,
            hiddenRawValue: hiddenRawValue
        )
    }

    private var primaryDestinations: [NavigationDestination] {
        NavigationRailConfiguration.visibleDestinations(
            orderRawValue: orderRawValue,
            hiddenRawValue: hiddenRawValue
        ).filter { $0 != .importMusic }
    }

    private var bottomDestinations: [NavigationDestination] {
        let visible = NavigationRailConfiguration.visibleDestinations(
            orderRawValue: orderRawValue,
            hiddenRawValue: hiddenRawValue
        )
        return (visible.contains(.importMusic) ? [.importMusic] : []) + [.trash]
    }

    private var expansionButton: some View {
        let accessibility = NavigationRailAccessibilityContract.items(
            sections: primarySections,
            isExpanded: isExpanded,
            selected: selection
        )[0]

        return Button {
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
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse Sidebar" : "Expand Sidebar")
        .accessibilityLabel(accessibility.label)
        .accessibilityHint(accessibility.hint)
    }

    private func railButton(_ destination: NavigationDestination) -> some View {
        let isSelected = !suppressesSelection && selection == destination
        let accessibility = NavigationRailAccessibilityContract.item(
            for: destination,
            selected: isSelected ? destination : nil
        )

        return Button {
            activationCounts[destination, default: 0] &+= 1
            selection = destination
        } label: {
            railLabel(
                systemName: destination.symbolName,
                title: destination.title,
                animationValue: activationCounts[destination, default: 0]
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background {
                BrowserRowSurface(
                    isSelected: isSelected,
                    isHovered: hoveredDestination == destination,
                    isFocused: focusedDestination == destination
                )
                .padding(.horizontal, NavigationRailMetrics.rowSurfaceInset)
            }
        }
        .buttonStyle(.plain)
        .focused($focusedDestination, equals: destination)
        .onHover { isInside in
            hoveredDestination = isInside ? destination : nil
        }
        .help(destination.title)
        .accessibilityLabel(accessibility.label)
        .accessibilityHint(accessibility.hint)
        .accessibilityValue(accessibility.value)
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
        animatesSymbolReplacement: Bool = false,
        animationValue: Int = 0
    ) -> some View {
        Group {
            if isExpanded {
                HStack(spacing: CadenceLayout.controlGap) {
                    railIcon(
                        systemName,
                        animatesSymbolReplacement: animatesSymbolReplacement,
                        animationValue: animationValue
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
                    animatesSymbolReplacement: animatesSymbolReplacement,
                    animationValue: animationValue
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
        animatesSymbolReplacement: Bool,
        animationValue: Int
    ) -> some View {
        Group {
            if animatesSymbolReplacement {
                if reduceMotion {
                    Image(systemName: systemName)
                } else {
                    Image(systemName: systemName)
                        .contentTransition(.symbolEffect(.replace))
                }
            } else {
                let motion = CadenceSymbolEffectPresentation.resolve(
                    trigger: animationValue,
                    reduceMotion: reduceMotion
                )
                if motion.isEnabled {
                    Image(systemName: systemName)
                        .symbolEffect(.bounce.up, value: motion.trigger)
                } else {
                    Image(systemName: systemName)
                }
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
    static let collapsedWidth: CGFloat = 64
    static let expandedWidth: CGFloat = 216
    static let horizontalInset = CadenceLayout.compactGap
    static let verticalInset = CadenceLayout.controlGap
    static let rowInset = CadenceLayout.compactGap
    static let rowSpacing = CadenceLayout.textStack
    static let rowSurfaceInset: CGFloat = 2
    static let rowHeight = CadenceLayout.rowHeight
    static let iconSlotWidth: CGFloat = 32

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
