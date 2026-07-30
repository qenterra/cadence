import SwiftUI

struct LyricsEditorHeader: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        HStack(spacing: 14) {
            Button {
                model.requestCloseLyricsEditor()
            } label: {
                Label("Back to Now Playing", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(width: 1, height: 20)

            Text("Lyrics Editor")
                .font(.title2.weight(.semibold))

            if model.isLyricDraftDirty {
                Text("Edited")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CadenceTheme.subduedFill, in: Capsule())
                    .accessibilityLabel("Unsaved changes")
            }

            if !model.lyricDraftValidationIssues.isEmpty {
                Label(
                    "\(model.lyricDraftValidationIssues.count) "
                        + "timing issue",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Spacer()

            Button("Cancel") {
                model.requestCloseLyricsEditor()
            }

            Button(model.isSavingLyricDraft ? "Saving…" : "Save") {
                Task {
                    await model.saveLyricDraftPersisting()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(!model.canSaveLyricDraft)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
    }
}
