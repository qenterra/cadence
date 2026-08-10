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
        VStack(spacing: 8) {
            expansionButton

            ForEach(primaryDestinations) { destination in
                railButton(destination)
            }
        }
    }

    private var primaryDestinations: [NavigationDestination] {
        NavigationRailConfiguration.visibleDestinations(
            orderRawValue: orderRawValue,
            hiddenRawValue: hiddenRawValue
        )
    }

    private var expansionButton: some View {
        Button {
            if reduceMotion {
                isExpanded.toggle()
            } else {
                withAnimation(.smooth(duration: 0.22)) {
                    isExpanded.toggle()
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(
                    systemName: isExpanded
                        ? "sidebar.left"
                        : "sidebar.right"
                )
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28)

                Text("Collapse")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .opacity(isExpanded ? 1 : 0)
                    .accessibilityHidden(!isExpanded)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, NavigationRailMetrics.rowInset)
            .frame(
                width: NavigationRailMetrics.rowWidth(
                    isExpanded: isExpanded
                ),
                height: NavigationRailMetrics.rowHeight,
                alignment: .leading
            )
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(CadenceRowButtonStyle())
        .help(isExpanded ? "Collapse Sidebar" : "Expand Sidebar")
    }

    private func railButton(_ destination: NavigationDestination) -> some View {
        let isSelected = !suppressesSelection && selection == destination

        return Button {
            selection = destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: destination.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 28)

                Text(destination.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .opacity(isExpanded ? 1 : 0)
                    .accessibilityHidden(!isExpanded)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, NavigationRailMetrics.rowInset)
            .frame(
                width: NavigationRailMetrics.rowWidth(
                    isExpanded: isExpanded
                ),
                height: NavigationRailMetrics.rowHeight,
                alignment: .leading
            )
            .clipped()
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
        .accessibilityValue(isSelected ? "Selected" : "")
        .frame(
            width: NavigationRailMetrics.contentWidth(
                isExpanded: isExpanded
            ),
            alignment: .center
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

    static func totalWidth(isExpanded: Bool) -> CGFloat {
        isExpanded ? expandedWidth : collapsedWidth
    }

    static func contentWidth(isExpanded: Bool) -> CGFloat {
        totalWidth(isExpanded: isExpanded) - horizontalInset * 2
    }

    static func rowWidth(isExpanded: Bool) -> CGFloat {
        isExpanded ? contentWidth(isExpanded: true) : rowHeight
    }
}
