import SwiftUI

struct SmartCollectionRuleRows: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                VStack(spacing: 0) {
                    switch row.node {
                    case let .condition(condition):
                        SmartCollectionConditionRow(
                            model: model,
                            condition: condition,
                            depth: row.depth
                        )
                    case let .group(group):
                        SmartCollectionGroupRow(
                            model: model,
                            group: group,
                            depth: row.depth
                        )
                    }

                    Rectangle()
                        .fill(CadenceTheme.separator)
                        .frame(height: 1)
                        .padding(.leading, CGFloat(row.depth) * 18)
                }
            }
        }
    }

    private var rows: [SmartCollectionRuleRow] {
        guard let rule = model.smartCollectionDraft?.rule else {
            return []
        }
        return SmartCollectionRuleTree(root: rule).rows
    }
}

private struct SmartCollectionGroupRow: View {
    @Bindable var model: CadenceAppModel

    let group: SmartCollectionRuleGroup
    let depth: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.down.right")
                .foregroundStyle(.tertiary)

            Text("Match")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "Group logic",
                selection: Binding(
                    get: { group.combinator },
                    set: {
                        model.setSmartCollectionCombinator(
                            $0,
                            groupID: group.id
                        )
                    }
                )
            ) {
                ForEach(SmartCollectionRuleCombinator.allCases) { combinator in
                    Text(combinator.title).tag(combinator)
                }
            }
            .labelsHidden()
            .frame(width: 84)

            Text("in this group")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Menu {
                Button("Add Rule", systemImage: "plus") {
                    model.addDefaultSmartCollectionCondition(to: group.id)
                }

                Button("Add Group", systemImage: "plus.square.on.square") {
                    model.addSmartCollectionGroup(to: group.id)
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuIndicator(.hidden)
            .help("Add to Group")

            Button {
                model.removeSmartCollectionRuleNode(group.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Remove Group")
            .accessibilityLabel("Remove Group")
        }
        .controlSize(.small)
        .padding(.leading, CGFloat(depth) * 18)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Group level \(depth + 1), match \(group.combinator.title)"
        )
    }
}

private struct SmartCollectionConditionRow: View {
    @Bindable var model: CadenceAppModel

    let condition: SmartCollectionRuleCondition
    let depth: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Button("NOT") {
                    model.toggleSmartCollectionNegation(
                        conditionID: condition.id
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(condition.isNegated ? .primary : .secondary)
                .accessibilityValue(condition.isNegated ? "Enabled" : "Disabled")

                Picker("Field", selection: fieldBinding) {
                    ForEach(availableFields) { field in
                        Text(field.title).tag(field)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 96)

                Picker("Operator", selection: operatorBinding) {
                    ForEach(condition.field.allowedOperators) { ruleOperator in
                        Text(ruleOperator.title).tag(ruleOperator)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 112)

                Spacer(minLength: 2)

                Button {
                    model.removeSmartCollectionRuleNode(condition.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Remove Rule")
                .accessibilityLabel("Remove Rule")
            }

            SmartCollectionRuleValueEditor(
                model: model,
                condition: condition
            )

            if let issue = model.smartCollectionValidation.issue(
                for: condition.id
            ) {
                Label(issue.message, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
        .padding(.leading, CGFloat(depth) * 18)
        .padding(.vertical, 10)
        .overlay(alignment: .leading) {
            if depth > 0 {
                Rectangle()
                    .fill(CadenceTheme.separator)
                    .frame(width: 1)
                    .padding(.leading, CGFloat(depth) * 18 - 9)
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.15),
            value: condition.field
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Rule level \(depth + 1), "
                + "\(condition.isNegated ? "not " : "")"
                + "\(condition.field.title) \(condition.operator.title)"
        )
    }

    private var availableFields: [SmartCollectionRuleField] {
        guard model.librarySession.availability != .preview else {
            return SmartCollectionRuleField.allCases
        }
        return SmartCollectionRuleField.productionCases
    }

    private var fieldBinding: Binding<SmartCollectionRuleField> {
        Binding(
            get: { condition.field },
            set: {
                model.replaceSmartCollectionField(
                    $0,
                    conditionID: condition.id
                )
            }
        )
    }

    private var operatorBinding: Binding<SmartCollectionRuleOperator> {
        Binding(
            get: { condition.operator },
            set: {
                model.updateSmartCollectionOperator(
                    $0,
                    conditionID: condition.id
                )
            }
        )
    }
}
