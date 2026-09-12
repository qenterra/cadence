import QenTerraComponents
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

    @Environment(\.visualRegressionFreezesHighlights)
    private var freezesVisualRegressionHighlights
    @AppStorage("navigationRail.expanded")
    private var isExpanded = NavigationRailConfiguration.defaultIsExpanded
    @AppStorage("navigationRail.order")
    private var orderRawValue = NavigationRailConfiguration.defaultOrderRawValue
    @AppStorage("navigationRail.hidden")
    private var hiddenRawValue = ""

    var body: some View {
        QenTerraComponents.NavigationRail(
            items: primaryDestinations.map(sharedItem),
            selection: $selection,
            footerItems: [sharedItem(.trash)],
            expansion: $isExpanded,
            expansionConfiguration: NavigationRailConfiguration.expansion,
            suppressesSelection: suppressesSelection,
            freezesInteractionHighlights: freezesVisualRegressionHighlights,
            presentation: .cadence
        )
    }

    private var primaryDestinations: [NavigationDestination] {
        NavigationRailConfiguration.visibleDestinations(
            orderRawValue: orderRawValue,
            hiddenRawValue: hiddenRawValue
        )
    }

    private func sharedItem(
        _ destination: NavigationDestination
    ) -> NavigationRailItem<NavigationDestination> {
        let accessibility = NavigationRailAccessibilityContract.item(
            for: destination,
            selected: selection
        )
        return NavigationRailItem(
            id: destination,
            title: accessibility.label,
            symbol: destination.symbolName,
            accessibilityHint: accessibility.hint
        )
    }
}

extension NavigationRailConfiguration {
    static var expansion: NavigationRailExpansionConfiguration {
        NavigationRailExpansionConfiguration(
            expandedTitle: String(localized: "Collapse"),
            collapsedTitle: String(localized: "Expand"),
            expandedSymbol: "sidebar.left",
            collapsedSymbol: "sidebar.right",
            expandedHint: String(localized: "Shows navigation as icons only"),
            collapsedHint: String(localized: "Shows navigation icons and labels"),
            expandedAccessibilityLabel: String(localized: "Collapse Sidebar"),
            collapsedAccessibilityLabel: String(localized: "Expand Sidebar")
        )
    }
}

enum NavigationRailMetrics {
    private static let shared = NavigationRailPresentation.cadence
    static let collapsedWidth = CGFloat(shared.compactWidth)
    static let expandedWidth = CGFloat(shared.expandedWidth)
    static let horizontalInset = CGFloat(shared.horizontalInset)
    static let rowSpacing = CGFloat(shared.rowSpacing)
    static let rowSurfaceInset = CGFloat(shared.rowSurfaceInset)
    static let rowHeight = CGFloat(shared.rowHeight)

    static func contentWidth(isExpanded: Bool) -> CGFloat {
        CGFloat(shared.contentWidth(isExpanded: isExpanded))
    }

    static func rowWidth(isExpanded: Bool) -> CGFloat {
        CGFloat(shared.rowWidth(isExpanded: isExpanded))
    }

    static func iconCenterX(isExpanded: Bool) -> CGFloat {
        CGFloat(shared.iconCenterX(isExpanded: isExpanded))
    }
}
