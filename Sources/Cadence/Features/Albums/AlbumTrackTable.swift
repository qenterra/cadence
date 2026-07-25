import SwiftUI

struct AlbumTrackTable: View {
    @Bindable var model: CadenceAppModel

    let album: AlbumPreview

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width - 56, 436)
            let columns = AlbumTrackTableColumnWidths(
                totalWidth: availableWidth
            )
            let tracks = AlbumListeningProjection.canonicalTracks(
                model.tracks.filter { $0.albumID == album.id }
            )
            let discs = Dictionary(grouping: tracks, by: \.discNumber)
            let discNumbers = discs.keys.sorted()

            VStack(spacing: 0) {
                AlbumTrackTableHeader(columns: columns)

                Rectangle()
                    .fill(CadenceTheme.separator)
                    .frame(height: 1)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(discNumbers, id: \.self) { discNumber in
                            if discNumbers.count > 1 {
                                Text("Disc \(discNumber)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.top, 14)
                                    .padding(.bottom, 5)
                            }

                            ForEach(discs[discNumber] ?? []) { track in
                                AlbumTrackRow(
                                    model: model,
                                    album: album,
                                    track: track,
                                    columns: columns
                                )
                                .frame(
                                    width: columns.total,
                                    alignment: .leading
                                )
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            .frame(width: availableWidth, alignment: .leading)
            .padding(.horizontal, 28)
        }
    }
}

private struct AlbumTrackTableHeader: View {
    let columns: AlbumTrackTableColumnWidths

    var body: some View {
        HStack(spacing: 0) {
            header("#", alignment: .center)
                .frame(width: columns.index)
            header("Title")
                .frame(width: columns.title)
            header("Format")
                .frame(width: columns.format)
            header("Time", alignment: .trailing)
                .frame(width: columns.duration)
            Color.clear
                .frame(width: columns.actions)
        }
        .frame(height: 38)
    }

    private func header(
        _ title: String,
        alignment: Alignment = .leading
    ) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, title == "#" ? 0 : 8)
    }
}
