import SwiftUI

struct TagEditorInspector: View {
    @Bindable var model: CadenceAppModel

    private let initialSearchQuery: String

    init(
        model: CadenceAppModel,
        initialSearchQuery: String = ""
    ) {
        self.model = model
        self.initialSearchQuery = initialSearchQuery
    }

    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TagEditorSearch(
                        model: model,
                        initialQuery: initialSearchQuery
                    )
                    TagEditorCurrentTags(model: model)
                    TagEditorSuggestions(model: model)
                }
                .padding(16)
            }
        }
        .background(CadenceTheme.secondarySurface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tag editor")
    }

    private var inspectorHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.tagEditingTitle)
                    .font(.headline)
                    .lineLimit(1)

                if let kind = model.tagEditingSelection.kind {
                    Text(selectionDescription(kind: kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 8)

            Button {
                model.isTagInspectorPresented = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(CadenceTheme.subduedFill, in: Circle())
            .contentShape(Circle())
            .help("Close Tag Editor")
            .accessibilityLabel("Close Tag Editor")
        }
        .padding(16)
    }

    private func selectionDescription(
        kind: TagEditingTargetKind
    ) -> String {
        let count = model.tagEditingSelection.count
        if count == 1 {
            return kind == .tracks ? "Track" : "Album"
        }
        return "\(count) \(kind.title)"
    }
}

struct TagEditorSectionHeader: View {
    let title: String
    let detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Spacer()

            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }
}
