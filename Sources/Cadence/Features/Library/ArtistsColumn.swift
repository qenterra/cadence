import SwiftUI

struct ArtistsColumn: View {
    @Bindable var model: CadenceAppModel

    @FocusState private var focusedArtistID: ArtistPreview.ID?
    @State private var hoveredArtistID: ArtistPreview.ID?

    var body: some View {
        VStack(spacing: 0) {
            LibraryColumnHeader(
                title: "Artists",
                detail: model.artists.count.formatted()
            )

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.artists) { artist in
                        artistRow(artist)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
    }

    private func artistRow(_ artist: ArtistPreview) -> some View {
        let isSelected = model.selectedArtistID == artist.id
        let isHovered = hoveredArtistID == artist.id
        let isFocused = focusedArtistID == artist.id

        return Button {
            model.selectArtist(artist)
        } label: {
            HStack(spacing: 12) {
                ArtistArtworkView(artist: artist)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(artist.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 12)
            .frame(height: 64)
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
        .focused($focusedArtistID, equals: artist.id)
        .onHover { isInside in
            hoveredArtistID = isInside ? artist.id : nil
        }
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}

private extension ArtistPreview {
    var detailText: String {
        let albumLabel = albumCount == 1 ? "album" : "albums"
        let trackLabel = trackCount == 1 ? "track" : "tracks"
        return "\(albumCount) \(albumLabel) · \(trackCount) \(trackLabel)"
    }
}
