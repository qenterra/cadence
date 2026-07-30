import SwiftUI

struct ArtistTagChips: View {
    @Bindable var model: CadenceAppModel

    let artist: ArtistPreview

    var body: some View {
        let tags = model.derivedTags(for: artist)

        if !tags.isEmpty {
            HStack(spacing: 8) {
                ForEach(tags.prefix(5)) { tag in
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
