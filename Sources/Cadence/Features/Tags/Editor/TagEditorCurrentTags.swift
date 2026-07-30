import SwiftUI

struct TagEditorCurrentTags: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TagEditorSectionHeader(
                "Current Tags",
                detail: model.tagSelectionSummaries.count.formatted()
            )

            if model.tagSelectionSummaries.isEmpty {
                Text("No tags are assigned to this selection.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.tagSelectionSummaries) { summary in
                        TagEditorCurrentTagRow(
                            model: model,
                            summary: summary,
                            undoManager: undoManager
                        )
                    }
                }
            }
        }
    }
}

private struct TagEditorCurrentTagRow: View {
    @Bindable var model: CadenceAppModel

    let summary: TagSelectionSummary
    let undoManager: UndoManager?

    var body: some View {
        HStack(spacing: 9) {
            tagIdentity

            Spacer(minLength: 6)

            if summary.excludeApplicableCount > 0 {
                Button("Exclude \(summary.excludeApplicableCount)") {
                    model.performTagEdit(
                        .excludeInherited(
                            tagID: summary.tag.id,
                            trackIDs: model.inheritedTrackIDs(for: summary.tag.id)
                        ),
                        undoManager: undoManager
                    )
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Exclude inherited tag from applicable tracks")
                .accessibilityLabel(
                    "Exclude \(summary.tag.displayPath) from "
                        + "\(summary.excludeApplicableCount) selected tracks"
                )
            }

            if summary.restoreApplicableCount > 0 {
                Button("Restore \(summary.restoreApplicableCount)") {
                    model.performTagEdit(
                        .restoreInheritance(
                            tagID: summary.tag.id,
                            trackIDs: model.excludedTrackIDs(for: summary.tag.id)
                        ),
                        undoManager: undoManager
                    )
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Restore album tag inheritance")
                .accessibilityLabel(
                    "Restore \(summary.tag.displayPath) for "
                        + "\(summary.restoreApplicableCount) selected tracks"
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CadenceTheme.subduedFill, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var tagIdentity: some View {
        if hasPrimaryAction {
            Button(action: activatePrimaryAction) {
                tagIdentityLabel
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(primaryActionHint)
        } else {
            tagIdentityLabel
        }
    }

    private var tagIdentityLabel: some View {
        HStack(spacing: 9) {
            Image(systemName: stateSymbolName)
                .foregroundStyle(stateForeground)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.tag.displayPath)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(summary.sourceDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.tag.displayPath)
        .accessibilityValue(summary.sourceDescription)
    }

    private var hasPrimaryAction: Bool {
        switch summary.state {
        case .allDirect, .mixedDirect, .mixedSource:
            true
        case .inherited, .excluded:
            false
        }
    }

    private var primaryActionHint: String {
        summary.state == .allDirect
            ? "Remove direct assignment"
            : "Assign directly to the complete selection"
    }

    private func activatePrimaryAction() {
        let command: TagEditCommand = if summary.state == .allDirect {
            .removeDirect(
                tagID: summary.tag.id,
                targets: model.tagEditingSelection.targets
            )
        } else {
            .assign(
                tagID: summary.tag.id,
                targets: model.tagEditingSelection.targets
            )
        }
        model.performTagEdit(command, undoManager: undoManager)
    }

    private var stateSymbolName: String {
        switch summary.state {
        case .allDirect:
            "checkmark.circle.fill"
        case .mixedDirect:
            "minus.circle"
        case .inherited:
            "arrow.down.to.line"
        case .excluded:
            "nosign"
        case .mixedSource:
            "square.stack.3d.up"
        }
    }

    private var stateForeground: some ShapeStyle {
        summary.state == .allDirect
            ? AnyShapeStyle(.tint)
            : AnyShapeStyle(.secondary)
    }
}
