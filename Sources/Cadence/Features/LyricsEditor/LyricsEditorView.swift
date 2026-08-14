import SwiftUI

struct LyricsEditorView: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        VStack(spacing: 0) {
            LyricsEditorHeader(model: model)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            if model.isLoadingLyricDraft {
                ProgressView("Loading Lyrics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.lyricDraft == nil {
                ContentUnavailableView {
                    Label(
                        "Couldn’t Open Lyrics",
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(
                        model.lyricPersistenceError
                            ?? "The managed lyric document is unavailable."
                    )
                } actions: {
                    Button("Retry") {
                        model.presentLyricsEditor()
                    }
                    Button("Back to Now Playing") {
                        model.requestCloseLyricsEditor()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.contentBackground)
        .onExitCommand {
            model.requestCloseLyricsEditor()
        }
        .alert(
            "Couldn’t Save Lyrics",
            isPresented: Binding(
                get: {
                    model.lyricDraft != nil
                        && model.lyricPersistenceError != nil
                },
                set: { isPresented in
                    if !isPresented {
                        model.dismissLyricPersistenceError()
                    }
                }
            )
        ) {
            Button("Retry") {
                Task {
                    await model.saveLyricDraftPersisting()
                }
            }
            Button("Cancel", role: .cancel) {
                model.dismissLyricPersistenceError()
            }
        } message: {
            Text(
                ProductErrorMessage(
                    detail: model.lyricPersistenceError
                        ?? String(localized: "Cadence could not save these lyrics."),
                    preservedState: String(localized: "Your draft remains open."),
                    recoveryAction: String(localized: "Retry or cancel saving.")
                ).text
            )
        }
    }
}
