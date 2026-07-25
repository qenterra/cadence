import SwiftUI

struct SmartCollectionRuleValueEditor: View {
    @Bindable var model: CadenceAppModel

    let condition: SmartCollectionRuleCondition

    var body: some View {
        switch condition.value {
        case let .tag(id, scope):
            tagEditor(id: id, scope: scope)
        case let .text(value):
            textEditor(value: value)
        case let .integer(value):
            integerEditor(value: value)
        case let .integerRange(lower, upper):
            rangeEditor(lower: lower, upper: upper)
        case let .boolean(value):
            booleanEditor(value: value)
        }
    }

    private func tagEditor(
        id: TagPreview.ID?,
        scope: SmartCollectionTagScope
    ) -> some View {
        HStack(spacing: 8) {
            Picker("Tag", selection: tagIDBinding(id: id, scope: scope)) {
                Text("Choose Tag").tag(nil as TagPreview.ID?)

                ForEach(sortedTags) { tag in
                    Text(tag.displayPath).tag(Optional(tag.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Picker("Tag Scope", selection: tagScopeBinding(id: id, scope: scope)) {
                ForEach(SmartCollectionTagScope.allCases) { tagScope in
                    Text(tagScope.title).tag(tagScope)
                }
            }
            .labelsHidden()
            .frame(width: 126)
        }
    }

    private func textEditor(value: String) -> some View {
        TextField(
            "Value",
            text: Binding(
                get: { value },
                set: {
                    model.updateSmartCollectionValue(
                        .text($0),
                        conditionID: condition.id
                    )
                }
            )
        )
        .textFieldStyle(.roundedBorder)
    }

    private func integerEditor(value: Int?) -> some View {
        TextField(
            condition.field == .year ? "Year" : "Rating",
            value: Binding(
                get: { value },
                set: {
                    model.updateSmartCollectionValue(
                        .integer($0),
                        conditionID: condition.id
                    )
                }
            ),
            format: .number.grouping(.never)
        )
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 150)
    }

    private func rangeEditor(
        lower: Int?,
        upper: Int?
    ) -> some View {
        HStack(spacing: 8) {
            TextField(
                "From",
                value: rangeBoundBinding(
                    lower: lower,
                    upper: upper,
                    editsLower: true
                ),
                format: .number.grouping(.never)
            )
            .textFieldStyle(.roundedBorder)

            Text("to")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(
                "To",
                value: rangeBoundBinding(
                    lower: lower,
                    upper: upper,
                    editsLower: false
                ),
                format: .number.grouping(.never)
            )
            .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: 230)
    }

    private func booleanEditor(value: Bool) -> some View {
        Picker(
            "Favorite",
            selection: Binding(
                get: { value },
                set: {
                    model.updateSmartCollectionValue(
                        .boolean($0),
                        conditionID: condition.id
                    )
                }
            )
        ) {
            Text("True").tag(true)
            Text("False").tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 130)
    }

    private func tagIDBinding(
        id: TagPreview.ID?,
        scope: SmartCollectionTagScope
    ) -> Binding<TagPreview.ID?> {
        Binding(
            get: { id },
            set: {
                model.updateSmartCollectionValue(
                    .tag(id: $0, scope: scope),
                    conditionID: condition.id
                )
            }
        )
    }

    private func tagScopeBinding(
        id: TagPreview.ID?,
        scope: SmartCollectionTagScope
    ) -> Binding<SmartCollectionTagScope> {
        Binding(
            get: { scope },
            set: {
                model.updateSmartCollectionValue(
                    .tag(id: id, scope: $0),
                    conditionID: condition.id
                )
            }
        )
    }

    private func rangeBoundBinding(
        lower: Int?,
        upper: Int?,
        editsLower: Bool
    ) -> Binding<Int?> {
        Binding(
            get: { editsLower ? lower : upper },
            set: { value in
                model.updateSmartCollectionValue(
                    .integerRange(
                        lower: editsLower ? value : lower,
                        upper: editsLower ? upper : value
                    ),
                    conditionID: condition.id
                )
            }
        )
    }

    private var sortedTags: [TagPreview] {
        model.tags.sorted {
            $0.displayPath.localizedStandardCompare($1.displayPath)
                == .orderedAscending
        }
    }
}
