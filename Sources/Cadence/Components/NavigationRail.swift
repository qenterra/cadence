import AppKit
import Observation
import QenTerraComponents
import SwiftUI

struct NavigationRailAccessibilityItem: Equatable, Sendable {
    let label: String
    let hint: String
    let value: String
}

@MainActor
@Observable
final class NavigationRailCommandState {
    private(set) var isPressed = false

    func update(modifierFlags: NSEvent.ModifierFlags) {
        isPressed = modifierFlags.contains(.command)
    }

    func reset() {
        isPressed = false
    }
}

enum NavigationRailCommandInteraction {
    static func activate(
        _ destination: NavigationDestination,
        selection: inout NavigationDestination
    ) {
        selection = destination
    }
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
    @State private var commandState = NavigationRailCommandState()

    var body: some View {
        ZStack(alignment: .topLeading) {
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

            if commandState.isPressed {
                NavigationRailCommandReorderOverlay(
                    destinations: primaryDestinations,
                    isExpanded: isExpanded,
                    selection: $selection,
                    reorder: reorder,
                    finishInteraction: commandState.reset
                )
            }

            CommandModifierObserver(state: commandState)
                .frame(width: 0, height: 0)
        }
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

    private func reorder(
        _ source: NavigationDestination,
        _ target: NavigationDestination
    ) {
        let current = NavigationRailConfiguration.orderedDestinations(
            from: orderRawValue
        )
        let reordered = NavigationRailConfiguration.moving(
            source,
            to: target,
            in: current
        )
        guard reordered != current else { return }
        withAnimation(.smooth(duration: CadenceTheme.motionDismiss)) {
            orderRawValue = NavigationRailConfiguration.encode(reordered)
        }
    }
}

private struct NavigationRailCommandReorderOverlay: View {
    let destinations: [NavigationDestination]
    let isExpanded: Bool
    @Binding var selection: NavigationDestination
    let reorder: (NavigationDestination, NavigationDestination) -> Void
    let finishInteraction: () -> Void

    @State private var dropTarget: NavigationDestination?

    var body: some View {
        VStack(spacing: NavigationRailMetrics.rowSpacing) {
            Color.clear
                .frame(height: NavigationRailMetrics.rowHeight)
                .padding(.bottom, CadenceLayout.controlGap)

            ForEach(destinations) { destination in
                Button {
                    NavigationRailCommandInteraction.activate(
                        destination,
                        selection: &selection
                    )
                    finishInteraction()
                } label: {
                    Color.black.opacity(0.001)
                        .frame(height: NavigationRailMetrics.rowHeight)
                        .background {
                            if dropTarget == destination {
                                RoundedRectangle(
                                    cornerRadius: CadenceTheme.radiusControl,
                                    style: .continuous
                                )
                                .fill(CadenceTheme.subduedFill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(destination.title)
                .onDrag {
                    NSItemProvider(
                        object: destination.rawValue as NSString
                    )
                } preview: {
                    Label(destination.title, systemImage: destination.symbolName)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .dropDestination(for: String.self) { values, _ in
                    guard
                        let rawValue = values.first,
                        let source = NavigationDestination(rawValue: rawValue)
                    else {
                        return false
                    }
                    reorder(source, destination)
                    dropTarget = nil
                    finishInteraction()
                    return true
                } isTargeted: {
                    dropTarget = $0 ? destination : nil
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: NavigationRailMetrics.contentWidth(isExpanded: isExpanded))
        .padding(.horizontal, NavigationRailMetrics.horizontalInset)
        .padding(.vertical, NavigationRailMetrics.verticalInset)
        .onDisappear { dropTarget = nil }
        .accessibilityHidden(true)
    }
}

struct CommandModifierObserver: NSViewRepresentable {
    let state: NavigationRailCommandState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_: NSView, context _: Context) {}

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        let state: NavigationRailCommandState
        private let notificationCenter: NotificationCenter
        private let focusLossNotifications: [Notification.Name]
        private var monitor: Any?
        private var notificationTokens: [NSObjectProtocol] = []

        init(
            state: NavigationRailCommandState,
            notificationCenter: NotificationCenter = .default,
            focusLossNotifications: [Notification.Name] = [
                NSApplication.didResignActiveNotification,
                NSWindow.didResignKeyNotification,
            ]
        ) {
            self.state = state
            self.notificationCenter = notificationCenter
            self.focusLossNotifications = focusLossNotifications
        }

        func start() {
            guard monitor == nil else { return }
            state.update(modifierFlags: NSEvent.modifierFlags)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.state.update(modifierFlags: event.modifierFlags)
                return event
            }
            notificationTokens = focusLossNotifications.map { name in
                notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main,
                    using: { [weak state] _ in
                        Task { @MainActor in state?.reset() }
                    }
                )
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            for token in notificationTokens {
                notificationCenter.removeObserver(token)
            }
            notificationTokens = []
            state.reset()
        }
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
    static let verticalInset = CGFloat(shared.verticalInset)
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
