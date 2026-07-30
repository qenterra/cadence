import SwiftUI

struct LyricsDraftTransitionAlert: ViewModifier {
    @Bindable var model: CadenceAppModel

    func body(content: Content) -> some View {
        content.alert(
            "Save Changes to Lyrics?",
            isPresented: Binding(
                get: { model.pendingLyricsTransition != nil },
                set: { _ in }
            )
        ) {
            Button("Save") {
                Task {
                    await model.resolvePendingLyricsTransitionPersisting(
                        .save
                    )
                }
            }
            .disabled(!model.canSaveLyricDraft)

            Button("Discard", role: .destructive) {
                Task {
                    await model.resolvePendingLyricsTransitionPersisting(
                        .discard
                    )
                }
            }

            Button("Cancel", role: .cancel) {
                Task {
                    await model.resolvePendingLyricsTransitionPersisting(
                        .cancel
                    )
                }
            }
        } message: {
            Text("Your unsaved line text and timing changes will be lost.")
        }
    }
}

extension View {
    func lyricsDraftTransitionAlert(
        model: CadenceAppModel
    ) -> some View {
        modifier(LyricsDraftTransitionAlert(model: model))
    }
}
