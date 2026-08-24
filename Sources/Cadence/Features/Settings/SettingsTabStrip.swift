import SwiftUI

struct SettingsTabStripMetrics: Equatable, Sendable {
    let iconFrame: CGSize
    let minimumTabSize: CGSize
    let rowSpacing: CGFloat

    static let standard = Self(
        iconFrame: CGSize(width: 24, height: 22),
        minimumTabSize: CGSize(width: 76, height: 54),
        rowSpacing: CadenceLayout.compactGap
    )

    static var iconFrame: CGSize {
        standard.iconFrame
    }

    static var minimumTabSize: CGSize {
        standard.minimumTabSize
    }

    static var rowSpacing: CGFloat {
        standard.rowSpacing
    }

    static func metrics(for _: CadenceSettingsTab) -> Self {
        standard
    }
}

struct SettingsTabStrip: View {
    @Binding var selection: CadenceSettingsTab

    var body: some View {
        HStack(spacing: SettingsTabStripMetrics.rowSpacing) {
            ForEach(CadenceSettingsTab.allCases) { tab in
                tabButton(tab)
            }
        }
    }

    private func tabButton(
        _ tab: CadenceSettingsTab
    ) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: CadenceLayout.textStack) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .frame(
                        width: SettingsTabStripMetrics.iconFrame.width,
                        height: SettingsTabStripMetrics.iconFrame.height
                    )
                Text(tab.title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(
                selection == tab ? CadenceTheme.primaryAccent : .secondary
            )
            .frame(
                minWidth: SettingsTabStripMetrics.minimumTabSize.width,
                minHeight: SettingsTabStripMetrics.minimumTabSize.height
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selection == tab ? "Selected" : "")
    }
}
