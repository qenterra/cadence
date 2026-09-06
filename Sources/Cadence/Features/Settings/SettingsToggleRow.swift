import QenTerraComponents
import SwiftUI

enum SettingsBooleanControlStyle: Equatable, Sendable {
    case nativeSwitch
}

enum SettingsBooleanControlSize: Equatable, Sendable {
    case small
}

enum SettingsBooleanControlAlignment: Equatable, Sendable {
    case trailing
}

enum SettingsBooleanControlPresentation {
    static let style = SettingsBooleanControlStyle.nativeSwitch
    static let size = SettingsBooleanControlSize.small
    static let alignment = SettingsBooleanControlAlignment.trailing
}

struct SettingsToggleRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    init(
        _ title: LocalizedStringKey,
        isOn: Binding<Bool>
    ) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        QenTerraComponents.SettingsToggleRow(
            title,
            isOn: $isOn,
            presentation: .cadence
        )
    }
}
