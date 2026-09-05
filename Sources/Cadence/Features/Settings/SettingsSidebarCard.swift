import SwiftUI

struct SettingsSidebarCard: View {
    @Binding var orderRawValue: String
    @Binding var hiddenRawValue: String
    @AppStorage("navigationRail.expanded")
    private var isSidebarExpanded = NavigationRailConfiguration.defaultIsExpanded

    @State private var draggedDestination: NavigationDestination?
    @State private var dropTarget: NavigationDestination?

    var body: some View {
        SettingsCard(
            title: "Navigation",
            symbol: "sidebar.left"
        ) {
            Text(
                "Choose which destinations appear. Drag a row to change "
                    + "its sidebar position."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(orderedDestinations) { destination in
                    sidebarRow(destination)

                    if destination != orderedDestinations.last {
                        Rectangle()
                            .fill(CadenceTheme.separator)
                            .frame(height: 0.5)
                    }
                }
            }
            .background(CadenceTheme.subduedFill)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusGroup
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusGroup
                )
                .strokeBorder(
                    CadenceTheme.separator,
                    lineWidth: 0.5
                )
            }

            HStack {
                Text("Reset restores the default order and makes every destination visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: CadenceLayout.contentGap)

                Button("Reset Sidebar", systemImage: "arrow.counterclockwise") {
                    resetSidebar()
                }
            }
        }
    }

    private var orderedDestinations: [NavigationDestination] {
        NavigationRailConfiguration.orderedDestinations(
            from: orderRawValue
        )
    }

    private func sidebarRow(
        _ destination: NavigationDestination
    ) -> some View {
        SettingsSidebarRow(
            destination: destination,
            isVisible: visibilityBinding(for: destination),
            isDragging: draggedDestination == destination,
            isDropTarget: dropTarget == destination,
            canMoveUp: canMove(destination, offset: -1),
            canMoveDown: canMove(destination, offset: 1),
            moveUp: {
                move(destination, offset: -1)
            },
            moveDown: {
                move(destination, offset: 1)
            }
        )
        .dropDestination(for: String.self) { values, _ in
            guard
                let rawValue = values.first,
                let source = NavigationDestination(rawValue: rawValue),
                NavigationRailConfiguration.configurableDestinations
                .contains(source)
            else {
                return false
            }

            reorder(source, to: destination)
            draggedDestination = nil
            dropTarget = nil
            return true
        } isTargeted: { isTargeted in
            dropTarget = isTargeted ? destination : nil
        }
        .onDrag {
            draggedDestination = destination
            return NSItemProvider(
                object: destination.rawValue as NSString
            )
        } preview: {
            SettingsSidebarDragPreview(destination: destination)
        }
    }

    private func visibilityBinding(
        for destination: NavigationDestination
    ) -> Binding<Bool> {
        Binding(
            get: {
                !NavigationRailConfiguration.hiddenDestinations(
                    from: hiddenRawValue
                ).contains(destination)
            },
            set: { isVisible in
                var hidden =
                    NavigationRailConfiguration.hiddenDestinations(
                        from: hiddenRawValue
                    )
                if isVisible {
                    hidden.remove(destination)
                } else {
                    hidden.insert(destination)
                }
                hiddenRawValue =
                    NavigationRailConfiguration.encode(hidden)
            }
        )
    }

    private func move(
        _ destination: NavigationDestination,
        offset: Int
    ) {
        guard
            canMove(destination, offset: offset),
            let sourceIndex = orderedDestinations.firstIndex(of: destination)
        else {
            return
        }
        reorder(
            destination,
            to: orderedDestinations[sourceIndex + offset]
        )
    }

    private func canMove(
        _ destination: NavigationDestination,
        offset: Int
    ) -> Bool {
        guard
            let sourceIndex = orderedDestinations.firstIndex(of: destination),
            orderedDestinations.indices.contains(sourceIndex + offset)
        else {
            return false
        }
        return true
    }

    private func reorder(
        _ source: NavigationDestination,
        to target: NavigationDestination
    ) {
        let reordered = NavigationRailConfiguration.moving(
            source,
            to: target,
            in: orderedDestinations
        )
        guard reordered != orderedDestinations else {
            return
        }

        withAnimation(.smooth(duration: CadenceTheme.motionDismiss)) {
            orderRawValue = NavigationRailConfiguration.encode(reordered)
        }
    }

    private func resetSidebar() {
        withAnimation(.smooth(duration: CadenceTheme.motionDismiss)) {
            orderRawValue = NavigationRailConfiguration.defaultOrderRawValue
            hiddenRawValue = ""
            isSidebarExpanded = NavigationRailConfiguration.defaultIsExpanded
        }
    }
}

private struct SettingsSidebarRow: View {
    let destination: NavigationDestination
    @Binding var isVisible: Bool
    let isDragging: Bool
    let isDropTarget: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: CadenceLayout.controlGap) {
            Toggle(isOn: $isVisible) {
                Label(
                    destination.title,
                    systemImage: destination.symbolName
                )
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: CadenceLayout.compactGap)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
                .help("Drag to Reorder")
        }
        .padding(.horizontal, CadenceLayout.controlGap)
        .frame(minHeight: CadenceLayout.rowHeight)
        .contentShape(Rectangle())
        .background {
            if isDropTarget {
                CadenceTheme.selectionFill
            }
        }
        .opacity(isDragging ? 0.48 : 1)
        .accessibilityActions {
            if canMoveUp {
                Button("Move Up", action: moveUp)
            }
            if canMoveDown {
                Button("Move Down", action: moveDown)
            }
        }
        .accessibilityHint(
            canMoveUp || canMoveDown
                ? "Drag to change the sidebar position."
                : ""
        )
    }
}

private struct SettingsSidebarDragPreview: View {
    let destination: NavigationDestination

    var body: some View {
        Label(
            destination.title,
            systemImage: destination.symbolName
        )
        .font(.body.weight(.medium))
        .padding(.horizontal, CadenceLayout.contentGap)
        .padding(.vertical, CadenceLayout.compactGap)
        .background(CadenceTheme.opaqueSurface)
        .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup))
        .overlay {
            RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup)
                .strokeBorder(CadenceTheme.strongSeparator, lineWidth: 0.5)
        }
    }
}
