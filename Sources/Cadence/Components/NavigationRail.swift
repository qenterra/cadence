import SwiftUI

struct NavigationRail: View {
    @Binding var selection: NavigationDestination

    var suppressesSelection = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedDestination: NavigationDestination?
    @State private var hoveredDestination: NavigationDestination?
    @AppStorage("navigationRail.expanded")
    private var isExpanded = false
    @AppStorage("navigationRail.order")
    private var orderRawValue = NavigationRailConfiguration.defaultOrderRawValue
    @AppStorage("navigationRail.hidden")
    private var hiddenRawValue = ""

    var body: some View {
        VStack(spacing: 8) {
            expansionButton

            ForEach(primaryDestinations) { destination in
                railButton(destination)
            }

            Spacer(minLength: 12)

            railButton(.trash)
            railButton(.settings)
        }
        .frame(width: 200, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(
            width: isExpanded ? 220 : 72,
            alignment: .leading
        )
        .clipped()
        .background(.thinMaterial)
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
            .frame(width: 180, height: 42, alignment: .leading)
            .padding(.horizontal, 10)
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
            .frame(width: 180, height: 42, alignment: .leading)
            .padding(.horizontal, 10)
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
    }
}
