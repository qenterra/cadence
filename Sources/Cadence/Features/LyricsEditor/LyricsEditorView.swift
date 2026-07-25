import SwiftUI

struct LyricsEditorView: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        VStack(spacing: 0) {
            LyricsEditorHeader(model: model)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            GeometryReader { geometry in
                let timingWidth = min(
                    max(geometry.size.width * 0.3, 300),
                    390
                )

                HStack(spacing: 0) {
                    LyricLineTable(model: model)
                        .frame(
                            width: geometry.size.width - timingWidth - 1
                        )

                    Rectangle()
                        .fill(CadenceTheme.separator)
                        .frame(width: 1)

                    TapToSyncPanel(model: model)
                        .frame(width: timingWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.contentBackground)
        .onExitCommand {
            model.requestCloseLyricsEditor()
        }
    }
}
