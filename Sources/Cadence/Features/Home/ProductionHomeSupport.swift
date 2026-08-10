import SwiftUI

enum HomeListeningSelection {
    static func continueTrack<Item>(from items: [Item]) -> Item? {
        items.first
    }

    static func items<Item>(_ items: [Item], limit: Int) -> [Item] {
        Array(items.prefix(max(limit, 0)))
    }
}

struct HomeShelf<Content: View>: View {
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2.bold())
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let actionTitle, let action {
                    Button(actionTitle, systemImage: "chevron.right") {
                        action()
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomeTrackGrid: View {
    @Bindable var model: CadenceAppModel
    let tracks: [LibraryTrackProjection]
    let queueSource: PlaybackQueueSource

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16),
            ],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(tracks) { track in
                Button {
                    model.playProductionTrack(
                        track,
                        within: tracks,
                        source: queueSource
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ProductionArtworkView(
                            model: model,
                            artworkID: track.artworkID,
                            title: track.title,
                            placeholder: .track,
                            cornerRadius: CadenceTheme.radiusGroup
                        )
                        .aspectRatio(1, contentMode: .fit)

                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(track.title) by \(track.artist)")
            }
        }
    }
}

struct HomeContinueListeningRow: View {
    @Bindable var model: CadenceAppModel
    let track: LibraryTrackProjection
    let queue: [LibraryTrackProjection]

    var body: some View {
        Button {
            model.playProductionTrack(
                track,
                within: queue,
                source: .adHoc
            )
        } label: {
            HStack(spacing: 14) {
                ProductionArtworkView(
                    model: model,
                    artworkID: track.artworkID,
                    title: track.title,
                    placeholder: .track,
                    cornerRadius: CadenceTheme.radiusControl
                )
                .frame(width: 68, height: 68)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !track.album.isEmpty {
                        Text(track.album)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 16)

                Image(systemName: "play.fill")
                    .font(.headline)
                    .frame(width: 34, height: 34)
                    .background(CadenceTheme.primaryAccent, in: Circle())
                    .foregroundStyle(.white)
            }
            .padding(12)
            .background(
                CadenceTheme.subduedFill,
                in: RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusGroup,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 620)
        .accessibilityLabel("Continue \(track.title) by \(track.artist)")
    }
}

struct HomeSubsectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

struct HomePinnedAlbumTile: View {
    @Bindable var model: CadenceAppModel
    let album: LibraryAlbumProjection

    var body: some View {
        Button {
            model.requestOpenProductionAlbumContextually(id: album.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ProductionArtworkView(
                    model: model,
                    artworkID: album.customArtworkID,
                    title: album.title,
                    placeholder: .album,
                    cornerRadius: CadenceTheme.radiusGroup
                )
                .aspectRatio(1, contentMode: .fit)
                Text(album.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct HomePinnedDestinationTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: symbol)
                    .frame(width: 28)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(12)
            .background(CadenceTheme.subduedFill)
            .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup))
        }
        .buttonStyle(CadenceRowButtonStyle())
    }
}
