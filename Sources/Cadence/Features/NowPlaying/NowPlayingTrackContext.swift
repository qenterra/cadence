import SwiftUI

struct NowPlayingTrackContext: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview
    let artworkSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Spacer(minLength: 16)

            ArtworkView(
                palette: track.artworkPalette,
                title: track.title,
                cornerRadius: 18,
                fillsAvailableSpace: true
            )
            .frame(width: artworkSize, height: artworkSize)
            .shadow(color: .black.opacity(0.28), radius: 28, y: 16)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 18)

            trackIdentity
            tags
            actions
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }

    private var header: some View {
        HStack {
            Button {
                model.dismissNowPlaying()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Back to \(model.selectedDestination.title)")

            Spacer()

            Text("Now Playing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
    }

    private var trackIdentity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(track.title)
                .font(.system(size: 28, weight: .semibold))
                .lineLimit(2)

            Text(track.artist)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("\(track.album) · \(track.yearText)")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var tags: some View {
        let effectiveTags = model.effectiveTags(for: track)

        if !effectiveTags.isEmpty {
            HStack(spacing: 7) {
                Image(systemName: "tag")
                    .foregroundStyle(.tertiary)

                ForEach(effectiveTags.prefix(3)) { tag in
                    Text(tag.displayPath)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            CadenceTheme.subduedFill,
                            in: Capsule()
                        )
                }

                if effectiveTags.count > 3 {
                    Menu {
                        ForEach(effectiveTags.dropFirst(3)) { tag in
                            Text(tag.displayPath)
                        }
                    } label: {
                        Text("+\(effectiveTags.count - 3)")
                            .font(.caption.weight(.semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Show all tags")
                }
            }
            .padding(.top, 16)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleFavorite(track)
            } label: {
                Label(
                    model.isFavorite(track) ? "Favorited" : "Favorite",
                    systemImage: model.isFavorite(track)
                        ? "heart.fill"
                        : "heart"
                )
            }
            .help(model.isFavorite(track) ? "Remove Favorite" : "Favorite")

            Button {
                model.dismissNowPlaying()
                model.openTagEditor(for: track)
            } label: {
                Label("Edit Tags", systemImage: "tag")
            }

            Menu {
                Text("\(track.format) · \(track.bitDepth)-bit")
                Text(track.sampleRateText)
                Text(track.fileSize)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuIndicator(.hidden)
            .help("More")
        }
        .controlSize(.regular)
        .padding(.top, 18)
    }
}
