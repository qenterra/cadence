import SwiftUI

struct SmartCollectionRuleBuilder: View {
    @Bindable var model: CadenceAppModel

    @FocusState private var isNameFocused: Bool

    var body: some View {
        if let draft = model.smartCollectionDraft {
            VStack(spacing: 0) {
                header(draft: draft)

                CadenceSeparator()

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        rootLogic(draft: draft)

                        if draft.rule.children.isEmpty {
                            emptyRuleHint
                        } else {
                            SmartCollectionRuleRows(model: model)
                        }

                        addRootControls(rootID: draft.rule.id)
                    }
                    .padding(14)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )
            .onAppear {
                focusNameIfRequested()
            }
            .onChange(of: model.smartCollectionNameFocusRequest) {
                focusNameIfRequested()
            }
        } else {
            ContentUnavailableView(
                "No Collection Selected",
                systemImage: "slider.horizontal.3",
                description: Text("Choose or create a Smart Collection.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(draft: SmartCollectionDraft) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                TextField(
                    "Collection Name",
                    text: Binding(
                        get: { draft.name },
                        set: model.renameSmartCollectionDraft
                    )
                )
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .focused($isNameFocused)
                .accessibilityLabel("Smart Collection name")

                if model.isSmartCollectionDraftDirty {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Unsaved changes")
                }

                Spacer(minLength: 8)

                Button("Done") {
                    model.requestFinishSmartCollectionEditing()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                editorStatus

                Spacer(minLength: 8)

                Button("Revert") {
                    model.revertSmartCollectionDraft()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!model.canRevertSmartCollectionDraft)

                Button("Save") {
                    Task {
                        await model.saveSmartCollectionDraftPersisting()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.canSaveSmartCollectionDraft)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 11)
    }

    @ViewBuilder
    private var editorStatus: some View {
        if let issue = model.smartCollectionValidation.nameIssue {
            Label(issue.message, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(
                model.smartCollectionDraft?.sourceID == nil
                    ? "New draft"
                    : "Saved collection"
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    private func rootLogic(draft: SmartCollectionDraft) -> some View {
        HStack {
            Text("Match")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "Root rule logic",
                selection: Binding(
                    get: { draft.rule.combinator },
                    set: {
                        model.setSmartCollectionCombinator(
                            $0,
                            groupID: draft.rule.id
                        )
                    }
                )
            ) {
                ForEach(SmartCollectionRuleCombinator.allCases) { combinator in
                    Text(combinator.title).tag(combinator)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 118)

            Text("of the following")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var emptyRuleHint: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("All tracks", systemImage: "music.note.list")
                .font(.body.weight(.medium))

            Text("Add a rule to narrow the collection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addRootControls(rootID: UUID) -> some View {
        HStack(spacing: 8) {
            Button {
                model.addDefaultSmartCollectionCondition(to: rootID)
            } label: {
                Label("Add Rule", systemImage: "plus")
            }

            Button {
                model.addSmartCollectionGroup(to: rootID)
            } label: {
                Label("Add Group", systemImage: "plus.square.on.square")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func focusNameIfRequested() {
        guard let request = model.smartCollectionNameFocusRequest else {
            return
        }
        isNameFocused = true
        model.consumeSmartCollectionNameFocusRequest(request)
    }
}
