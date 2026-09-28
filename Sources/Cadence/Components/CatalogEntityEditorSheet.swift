import SwiftUI

struct CatalogEntityEditorSheet: View {
    @Bindable var model: CadenceAppModel

    let title: String
    let fieldLabel: String
    let descriptionFieldLabel: String?
    let artworkTarget: ArtworkTarget?
    let artworkLabel: String?
    let maximumLength: Int?
    let normalizeValue: (String) -> String
    let validationMessage: (String) -> String?
    let save: @MainActor (String, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var descriptionDraft: String
    @State private var isSaving = false

    init(
        model: CadenceAppModel,
        title: String,
        fieldLabel: String,
        initialValue: String,
        artworkTarget: ArtworkTarget? = nil,
        artworkLabel: String? = nil,
        maximumLength: Int? = nil,
        normalizeValue: @escaping (String) -> String = {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        },
        validationMessage: @escaping (String) -> String? = { _ in nil },
        save: @escaping @MainActor (String) async -> Bool
    ) {
        self.model = model
        self.title = title
        self.fieldLabel = fieldLabel
        descriptionFieldLabel = nil
        self.artworkTarget = artworkTarget
        self.artworkLabel = artworkLabel
        self.maximumLength = maximumLength
        self.normalizeValue = normalizeValue
        self.validationMessage = validationMessage
        self.save = { value, _ in await save(value) }
        _draft = State(initialValue: initialValue)
        _descriptionDraft = State(initialValue: "")
    }

    init(
        model: CadenceAppModel,
        title: String,
        fieldLabel: String,
        initialValue: String,
        descriptionFieldLabel: String,
        initialDescription: String?,
        artworkTarget: ArtworkTarget? = nil,
        artworkLabel: String? = nil,
        maximumLength: Int? = nil,
        normalizeValue: @escaping (String) -> String = {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        },
        validationMessage: @escaping (String) -> String? = { _ in nil },
        save: @escaping @MainActor (String, String?) async -> Bool
    ) {
        self.model = model
        self.title = title
        self.fieldLabel = fieldLabel
        self.descriptionFieldLabel = descriptionFieldLabel
        self.artworkTarget = artworkTarget
        self.artworkLabel = artworkLabel
        self.maximumLength = maximumLength
        self.normalizeValue = normalizeValue
        self.validationMessage = validationMessage
        self.save = save
        _draft = State(initialValue: initialValue)
        _descriptionDraft = State(initialValue: initialDescription ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(title, systemImage: "pencil")
                    .font(.headline)
                Spacer()
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(fieldLabel, text: $draft)
                        .textFieldStyle(.roundedBorder)

                    if let maximumLength {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if let validationMessage = currentValidationMessage {
                                Label(
                                    validationMessage,
                                    systemImage: "exclamationmark.circle"
                                )
                            }
                            Spacer(minLength: 8)
                            Text("\(normalizedDraft.count) of \(maximumLength) characters")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if let descriptionFieldLabel {
                    TextField(
                        descriptionFieldLabel,
                        text: $descriptionDraft,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2 ... 4)
                }

                if let artworkTarget, let artworkLabel {
                    ArtworkActionButtons(
                        model: model,
                        target: artworkTarget,
                        label: artworkLabel
                    )
                }
            }
            .padding(20)

            Divider()

            HStack {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
                Button("Save") {
                    let value = normalizedDraft
                    Task { @MainActor in
                        isSaving = true
                        if await save(
                            value,
                            CatalogDescriptionPolicy.normalized(descriptionDraft)
                        ) {
                            dismiss()
                        }
                        isSaving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .cadenceActionTint(.confirmation)
                .disabled(
                    normalizedDraft.isEmpty
                        || currentValidationMessage != nil
                        || isSaving
                )
            }
            .padding(20)
        }
        .frame(width: 440)
        .background(CadenceTheme.opaqueSurface)
        .interactiveDismissDisabled(isSaving)
    }

    private var normalizedDraft: String {
        normalizeValue(draft)
    }

    private var currentValidationMessage: String? {
        validationMessage(draft)
    }
}
