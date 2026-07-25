import SwiftUI

struct NowPlayingPanelPicker: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        Picker(
            "Now Playing Panel",
            selection: Binding(
                get: { model.selectedNowPlayingPanel },
                set: model.selectNowPlayingPanel
            )
        ) {
            ForEach(NowPlayingPanel.allCases) { panel in
                Text(panel.title).tag(panel)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 184)
        .accessibilityLabel("Now Playing content")
    }
}
