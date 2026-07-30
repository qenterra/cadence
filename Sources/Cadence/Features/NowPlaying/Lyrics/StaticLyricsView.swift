import SwiftUI

struct StaticLyricsView: View {
    @Bindable var model: CadenceAppModel

    let document: LyricDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(statusTitle, systemImage: "text.alignleft")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Edit Lyrics", systemImage: "pencil") {
                    model.presentLyricsEditor()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            ScrollView {
                Text(staticText)
                    .font(.system(size: 22, weight: .medium))
                    .lineSpacing(7)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 48)
            }
        }
    }

    private var statusTitle: String {
        switch document.timingStatus {
        case .partiallySynchronized:
            "Partially synchronized"
        case .unsynchronized:
            "Static lyrics"
        case .synchronized:
            "Synchronized"
        case .missing:
            "No lyrics"
        }
    }

    private var staticText: String {
        document.lines.map(\.text).joined(separator: "\n")
    }
}
