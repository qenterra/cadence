import SwiftUI

struct SettingsSidebarCard: View {
    @Binding var orderRawValue: String
    @Binding var hiddenRawValue: String

    @State private var draggedDestination: NavigationDestination?
    @State private var dropTarget: NavigationDestination?

    var body: some View {
        SettingsCard(
            title: "Navigation",
            symbol: "sidebar.left"
        ) {
            Text(
                "Choose which destinations appear. Drag a row to change "
                    + "its position within a section."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(spacing: 14) {
                ForEach(orderedSections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)

                        VStack(spacing: 0) {
                            ForEach(section.destinations) { destination in
                                sidebarRow(destination)

                                if destination != section.destinations.last {
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
                    }
                }
            }
        }
    }

    private var orderedDestinations: [NavigationDestination] {
        NavigationRailConfiguration.orderedDestinations(
            from: orderRawValue
        )
    }

    private var orderedSections: [NavigationRailSection] {
        NavigationRailConfiguration.visibleSections(
            orderRawValue: orderRawValue,
            hiddenRawValue: ""
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
            canMoveUp: destinations(in: destination).first != destination,
            canMoveDown: destinations(in: destination).last != destination,
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
                .contains(source),
                source.navigationGroup == destination.navigationGroup
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
        let destinations = destinations(in: destination)
        guard
            let sourceIndex = destinations.firstIndex(of: destination),
            destinations.indices.contains(sourceIndex + offset)
        else {
            return
        }
        reorder(
            destination,
            to: destinations[sourceIndex + offset]
        )
    }

    private func destinations(
        in destination: NavigationDestination
    ) -> [NavigationDestination] {
        orderedSections.first {
            $0.group == destination.navigationGroup
        }?.destinations ?? []
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
