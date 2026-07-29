import SwiftUI

struct TrackTagPopover: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview
    let dismiss: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let items = model.trackTagItems(for: track)

        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text("No tags assigned")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                ForEach(items) { item in
                    Button {
                        dismiss()
                        model.requestOpenTagContextually(item.tag)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: symbol(for: item.source))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.tag.displayPath)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .strikethrough(item.source == .excluded)

                                Text(item.source.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(item.source.title)
                }
            }

            Divider()

            Button {
                dismiss()
                model.openTagEditor(for: track)
            } label: {
                Label("Edit Tags", systemImage: "pencil")
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 250)
        .background(
            CadenceTheme.opaqueSurface,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(contrast == .increased ? 0.46 : 0.12)
                )
        }
    }

    private func symbol(for source: AlbumTrackTagSource) -> String {
        switch source {
        case .direct:
            "tag.fill"
        case .inherited:
            "arrow.turn.down.right"
        case .excluded:
            "minus.circle"
        }
    }
}
