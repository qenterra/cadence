import SwiftUI

struct NavigationRail: View {
    @Binding var selection: NavigationDestination

    var suppressesSelection = false

    @FocusState private var focusedDestination: NavigationDestination?
    @State private var hoveredDestination: NavigationDestination?

    private let primaryDestinations: [NavigationDestination] = [
        .library,
        .albums,
        .artists,
        .tags,
        .graph,
        .smartCollections,
        .importFolder,
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(primaryDestinations) { destination in
                railButton(destination)
            }

            Spacer(minLength: 12)

            railButton(.settings)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(width: 72)
        .background(.thinMaterial)
    }

    private func railButton(_ destination: NavigationDestination) -> some View {
        let isSelected = !suppressesSelection && selection == destination

        return Button {
            selection = destination
        } label: {
            Image(systemName: destination.symbolName)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 48, height: 42)
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
