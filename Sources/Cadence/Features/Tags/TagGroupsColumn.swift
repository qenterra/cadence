import SwiftUI

struct TagGroupsColumn: View {
    @Bindable var model: CadenceAppModel

    @FocusState private var focusedGroupID: TagGroupID?
    @State private var hoveredGroupID: TagGroupID?

    var body: some View {
        VStack(spacing: 0) {
            LibraryColumnHeader(
                title: "Tag Groups",
                detail: model.tagGroups.count.formatted()
            )

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(model.tagGroups) { group in
                        groupRow(group)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
    }

    private func groupRow(_ group: TagGroupPreview) -> some View {
        let isSelected = model.selectedTagGroupID == group.id

        return Button {
            model.selectTagGroup(group)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: group.id.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 18)

                Text(group.title)
                    .font(.body.weight(isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(group.tagCount.formatted())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background {
                BrowserRowSurface(
                    isSelected: isSelected,
                    isHovered: hoveredGroupID == group.id,
                    isFocused: focusedGroupID == group.id
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(CadenceRowButtonStyle())
        .focused($focusedGroupID, equals: group.id)
        .onHover { isInside in
            hoveredGroupID = isInside ? group.id : nil
        }
        .accessibilityLabel("\(group.title), \(group.tagCount) tags")
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}

private extension TagGroupID {
    var symbolName: String {
        switch self {
        case .all:
            "tag"
        case let .hierarchy(name):
            switch name {
            case "genre":
                "music.note"
            case "mood":
                "face.smiling"
            case "context":
                "moon.stars"
            default:
                "folder"
            }
        case .standalone:
            "tag.circle"
        }
    }
}
