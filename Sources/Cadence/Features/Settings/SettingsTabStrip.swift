import QenTerraComponents
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
        TabStrip(
            items: CadenceSettingsTab.allCases.map {
                TabItem(
                    id: $0,
                    title: $0.title,
                    symbol: $0.symbolName
                )
            },
            selection: $selection,
            presentation: .cadenceSettings
        )
    }
}
