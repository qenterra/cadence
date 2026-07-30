import SwiftUI

struct AlbumTagChips: View {
    @Bindable var model: CadenceAppModel

    let album: AlbumPreview

    var body: some View {
        let assignedTags = model.assignedTags(for: album)

        if !assignedTags.isEmpty {
            HStack(spacing: 8) {
                ForEach(assignedTags.prefix(4)) { tag in
                    Button {
                        model.requestOpenTagContextually(tag)
                    } label: {
                        Label(tag.displayPath, systemImage: "tag")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open \(tag.displayPath) in Tags")
                }
            }
        }
    }
}
