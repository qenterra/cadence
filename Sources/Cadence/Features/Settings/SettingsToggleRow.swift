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
        HStack(spacing: CadenceLayout.controlGap) {
            Text(title)
                .accessibilityHidden(true)

            Spacer(minLength: CadenceLayout.contentGap)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
