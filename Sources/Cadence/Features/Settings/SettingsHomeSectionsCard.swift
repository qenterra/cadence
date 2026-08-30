import SwiftUI

struct SettingsHomeSectionsCard: View {
    @Binding var orderRawValue: String
    @Binding var hiddenRawValue: String

    @State private var draggedSection: HomeContentSection?
    @State private var dropTarget: HomeContentSection?

    var body: some View {
        SettingsCard(title: "Home", symbol: "house") {
            Text(
                "Recently Played always stays first. Choose which other sections appear and drag them into order."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                fixedRecentlyPlayedRow
                SettingsRowSeparator()

                ForEach(orderedSections) { section in
                    configurableRow(section)
                    if section != orderedSections.last {
                        SettingsRowSeparator()
                    }
                }
            }
            .background(CadenceTheme.subduedFill)
            .clipShape(
                RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup)
                    .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
            }

            HStack {
                Spacer()
                Button("Reset Home", systemImage: "arrow.counterclockwise") {
                    withAnimation(.smooth(duration: CadenceTheme.motionDismiss)) {
                        orderRawValue = HomeSectionConfiguration.defaultOrderRawValue
                        hiddenRawValue = ""
                    }
                }
            }
        }
    }

    private var fixedRecentlyPlayedRow: some View {
        HStack(spacing: CadenceLayout.controlGap) {
            Toggle(isOn: .constant(true)) {
                Label(
                    HomeContentSection.recentlyPlayed.title,
                    systemImage: HomeContentSection.recentlyPlayed.symbolName
                )
            }
            .toggleStyle(.checkbox)
            .disabled(true)

            Spacer(minLength: CadenceLayout.compactGap)

            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
                .help("Recently Played always stays first")
        }
        .padding(.horizontal, CadenceLayout.controlGap)
        .frame(minHeight: CadenceLayout.rowHeight)
    }

    private var orderedSections: [HomeContentSection] {
        HomeSectionConfiguration.orderedConfigurableSections(
            from: orderRawValue
        )
    }

    private func configurableRow(
        _ section: HomeContentSection
    ) -> some View {
        HStack(spacing: CadenceLayout.controlGap) {
            Toggle(isOn: visibilityBinding(for: section)) {
                Label(section.title, systemImage: section.symbolName)
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
            if dropTarget == section {
                CadenceTheme.selectionFill
            }
        }
        .opacity(draggedSection == section ? 0.48 : 1)
        .onDrag {
            draggedSection = section
            return NSItemProvider(object: section.rawValue as NSString)
        }
        .dropDestination(for: String.self) { values, _ in
            guard
                let rawValue = values.first,
                let source = HomeContentSection(rawValue: rawValue)
            else {
                return false
            }
            reorder(source, to: section)
            draggedSection = nil
            dropTarget = nil
            return true
        } isTargeted: { targeted in
            dropTarget = targeted ? section : nil
        }
    }

    private func visibilityBinding(
        for section: HomeContentSection
    ) -> Binding<Bool> {
        Binding(
            get: {
                !HomeSectionConfiguration.hiddenSections(
                    from: hiddenRawValue
                ).contains(section)
            },
            set: { isVisible in
                var hidden = HomeSectionConfiguration.hiddenSections(
                    from: hiddenRawValue
                )
                if isVisible {
                    hidden.remove(section)
                } else {
                    hidden.insert(section)
                }
                hiddenRawValue = HomeSectionConfiguration.encode(hidden)
            }
        )
    }

    private func reorder(
        _ source: HomeContentSection,
        to target: HomeContentSection
    ) {
        let reordered = HomeSectionConfiguration.moving(
            source,
            to: target,
            in: orderedSections
        )
        guard reordered != orderedSections else {
            return
        }
        withAnimation(.smooth(duration: CadenceTheme.motionDismiss)) {
            orderRawValue = HomeSectionConfiguration.encode(reordered)
        }
    }
}

private struct SettingsRowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(CadenceTheme.separator)
            .frame(height: 0.5)
    }
}
