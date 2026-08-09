import SwiftUI

struct GuideChapterPickerView: View {
    @Bindable var coordinator: GuideCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cadence Guide")
                        .font(.largeTitle.bold())
                    Text("Take the complete tour or jump to one focused chapter.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    coordinator.dismissChapterPicker()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(28)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(0 ..< 3, id: \.self) { row in
                    GridRow {
                        ForEach(0 ..< 2, id: \.self) { column in
                            chapterButton(
                                GuideCatalog.allChapters[row * 2 + column]
                            )
                        }
                    }
                }
            }
            .padding(24)

            Spacer(minLength: 0)
        }
        .frame(width: 620, height: 570)
        .background(CadenceTheme.contentBackground)
        .accessibilityIdentifier("Cadence.Guide.ChapterPicker")
    }

    private func chapterButton(_ chapter: GuideChapter) -> some View {
        Button {
            coordinator.start(chapter.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                chapterIcon(chapter)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(chapter.id.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    Text(chapter.id.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text("\(chapter.steps.count) steps")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(
                CadenceTheme.secondarySurface,
                in: RoundedRectangle(cornerRadius: CadenceTheme.radiusPanel)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CadenceTheme.radiusPanel)
                    .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusPanel))
        }
        .buttonStyle(CadenceRowButtonStyle())
        .accessibilityLabel(
            "\(chapter.id.title), \(chapter.steps.count) steps"
        )
        .accessibilityHint(chapter.id.subtitle)
        .accessibilityIdentifier(
            "Cadence.Guide.Chapter.\(chapter.id.rawValue)"
        )
    }

    private func chapterIcon(_ chapter: GuideChapter) -> some View {
        Image(systemName: chapter.id.symbolName)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 38, height: 38)
            .background(
                CadenceTheme.subduedFill,
                in: RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup)
            )
    }
}
