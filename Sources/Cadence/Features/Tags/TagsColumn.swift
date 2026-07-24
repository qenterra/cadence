import SwiftUI

struct TagsColumn: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedTagID: TagPreview.ID?
    @State private var hoveredTagID: TagPreview.ID?

    var body: some View {
        VStack(spacing: 0) {
            LibraryColumnHeader(
                title: model.selectedTagGroupID.title,
                detail: model.tagsForSelectedGroup.count.formatted()
            )

            ZStack {
                if model.tagsForSelectedGroup.isEmpty {
                    ContentUnavailableView(
                        "No Tags",
                        systemImage: "tag",
                        description: Text("This group has no assigned tags.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(model.tagsForSelectedGroup) { tag in
                                tagRow(tag)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 16)
                    }
                }
            }
            .id(model.selectedTagGroupID)
            .transition(.opacity)
            .animation(columnTransition, value: model.selectedTagGroupID)
        }
    }

    private func tagRow(_ tag: TagPreview) -> some View {
        let isSelected = model.selectedTagID == tag.id

        return Button {
            model.selectTag(tag)
        } label: {
            HStack(spacing: 10) {
                Text(rowTitle(for: tag))
                    .font(.body.weight(isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(model.trackCount(for: tag).formatted())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background {
                BrowserRowSurface(
                    isSelected: isSelected,
                    isHovered: hoveredTagID == tag.id,
                    isFocused: focusedTagID == tag.id
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(CadenceRowButtonStyle())
        .focused($focusedTagID, equals: tag.id)
        .onHover { isInside in
            hoveredTagID = isInside ? tag.id : nil
        }
        .accessibilityLabel("\(tag.displayPath), \(model.trackCount(for: tag)) tracks")
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private func rowTitle(for tag: TagPreview) -> String {
        model.selectedTagGroupID == .all
            ? tag.displayPath
            : tag.displayName
    }

    private var columnTransition: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }
}
