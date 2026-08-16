import SwiftUI

enum SettingsTabControlPresentation: Equatable, Sendable {
    case nativeGlass
    case stableOpaque

    static func resolve(
        usesStableSystemControls: Bool
    ) -> Self {
        usesStableSystemControls ? .stableOpaque : .nativeGlass
    }
}

struct SettingsTabStrip: View {
    @Environment(\.visualRegressionUsesStableSystemControls)
    private var usesStableSystemControls
    @Binding var selection: CadenceSettingsTab

    var body: some View {
        switch SettingsTabControlPresentation.resolve(
            usesStableSystemControls: usesStableSystemControls
        ) {
        case .nativeGlass:
            GlassEffectContainer(spacing: CadenceLayout.compactGap) {
                tabRow(usesNativeGlass: true)
            }
        case .stableOpaque:
            tabRow(usesNativeGlass: false)
        }
    }

    private func tabRow(
        usesNativeGlass: Bool
    ) -> some View {
        HStack(spacing: CadenceLayout.compactGap) {
            ForEach(CadenceSettingsTab.allCases) { tab in
                if usesNativeGlass, selection == tab {
                    tabButton(tab)
                        .buttonStyle(.glass)
                } else {
                    tabButton(tab)
                        .buttonStyle(.plain)
                        .background {
                            if !usesNativeGlass, selection == tab {
                                RoundedRectangle(
                                    cornerRadius: CadenceTheme.radiusControl,
                                    style: .continuous
                                )
                                .fill(CadenceTheme.secondarySurface)
                            }
                        }
                }
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
                    .frame(width: 24, height: 22)
                Text(tab.title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(selection == tab ? .primary : .secondary)
            .frame(minWidth: 76, minHeight: 54)
            .contentShape(Rectangle())
        }
        .accessibilityValue(selection == tab ? "Selected" : "")
    }
}
