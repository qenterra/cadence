import SwiftUI

struct TagEditorSuggestions: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TagEditorSectionHeader(
                "Suggestions",
                detail: model.tagSuggestions.count.formatted()
            )

            if model.tagSuggestions.isEmpty {
                Text("Cadence found no useful suggestions for this selection.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(model.tagSuggestions) { suggestion in
                        suggestionRow(suggestion)
                    }
                }
            }
        }
    }

    private func suggestionRow(
        _ suggestion: TagSuggestion
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(suggestion.tag.displayPath, systemImage: "sparkles")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text(suggestion.eligibilityDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Accept") {
                    model.performTagEdit(
                        .acceptSuggestion(
                            tagID: suggestion.tag.id,
                            targets: suggestion.eligibleTargets
                        ),
                        undoManager: undoManager
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel(
                    "Accept \(suggestion.tag.displayPath) suggestion"
                )

                Button("Dismiss") {
                    model.performTagEdit(
                        .dismissSuggestion(
                            tagID: suggestion.tag.id,
                            targets: suggestion.eligibleTargets
                        ),
                        undoManager: undoManager
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(
                    "Dismiss \(suggestion.tag.displayPath) suggestion"
                )
            }
        }
        .padding(10)
        .background(CadenceTheme.opaqueSurface, in: .rect(cornerRadius: 9))
        .accessibilityElement(children: .contain)
    }
}
