import SwiftUI

struct AlbumsColumn: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedAlbumID: AlbumPreview.ID?
    @State private var hoveredAlbumID: AlbumPreview.ID?

    var body: some View {
        VStack(spacing: 0) {
            LibraryColumnHeader(
                title: "Albums",
                detail: model.albumsForSelectedArtist.count.formatted()
            )

            ZStack {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.albumsForSelectedArtist) { album in
                            albumRow(album)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .id(model.selectedArtistID)
                .transition(.opacity)
            }
            .animation(columnTransition, value: model.selectedArtistID)
        }
    }

    private func albumRow(_ album: AlbumPreview) -> some View {
        let isSelected = model.selectedAlbumID == album.id
        let isHovered = hoveredAlbumID == album.id
        let isFocused = focusedAlbumID == album.id

        return Button {
            model.selectAlbum(album)
        } label: {
            HStack(spacing: 14) {
                ArtworkView(
                    palette: album.artworkPalette,
                    title: album.title,
                    cornerRadius: 7
                )
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 5) {
                    Text(album.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(album.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("\(album.trackCount) tracks · \(album.durationText)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .frame(height: 104)
            .background {
                BrowserRowSurface(
                    isSelected: isSelected,
                    isHovered: isHovered,
                    isFocused: isFocused
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(CadenceRowButtonStyle())
        .focused($focusedAlbumID, equals: album.id)
        .onHover { isInside in
            hoveredAlbumID = isInside ? album.id : nil
        }
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var columnTransition: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }
}
