import SwiftUI

enum HomeListeningSelection {
    static func items<Item>(_ items: [Item], limit: Int) -> [Item] {
        Array(items.prefix(max(limit, 0)))
    }

    static func recentItems<Item: Identifiable>(
        _ items: [Item],
        excludingID: Item.ID?,
        limit: Int
    ) -> [Item] where Item.ID: Equatable {
        guard limit > 0 else {
            return []
        }
        return Array(
            items.lazy.filter { item in
                guard let excludingID else {
                    return true
                }
                return item.id != excludingID
            }.prefix(limit)
        )
    }
}

struct HomeFavoritesPreviewBudget: Equatable {
    let trackLimit: Int
    let albumLimit: Int
    let artistLimit: Int

    static func resolve(
        trackCount: Int,
        albumCount: Int,
        artistCount: Int,
        limit: Int
    ) -> HomeFavoritesPreviewBudget {
        let capacities = [trackCount, albumCount, artistCount].map {
            max($0, 0)
        }
        var allocations = [0, 0, 0]
        let resolvedLimit = max(limit, 0)
        var allocatedCount = 0

        while allocatedCount < resolvedLimit {
            var allocatedItem = false
            for index in allocations.indices
                where allocations[index] < capacities[index] {
                allocations[index] += 1
                allocatedCount += 1
                allocatedItem = true
                if allocatedCount == resolvedLimit {
                    break
                }
            }
            if !allocatedItem {
                break
            }
        }

        return HomeFavoritesPreviewBudget(
            trackLimit: allocations[0],
            albumLimit: allocations[1],
            artistLimit: allocations[2]
        )
    }
}

struct HomeShelf<Content: View>: View {
    let title: String
    let subtitle: String?
    let actionTitle: String?
    let action: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
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
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let actionTitle, let action {
                    Button(action: action) {
                        HStack(spacing: 5) {
                            Text(actionTitle)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                    }
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
                GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 12),
            ],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(tracks) { track in
                HomeTrackTile(
                    model: model,
                    track: track,
                    queue: tracks,
                    queueSource: queueSource
                )
            }
        }
    }
}

struct HomeTrackTile: View {
    @Bindable var model: CadenceAppModel
    let track: LibraryTrackProjection
    let queue: [LibraryTrackProjection]
    let queueSource: PlaybackQueueSource
    @State private var isHovered = false

    var body: some View {
        Button {
            model.playProductionTrack(
                track,
                within: queue,
                source: queueSource
            )
        } label: {
            HStack(spacing: 12) {
                ProductionArtworkView(
                    model: model,
                    artworkID: track.artworkID,
                    title: track.title,
                    placeholder: .track,
                    cornerRadius: CadenceTheme.radiusControl
                )
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        isHovered ? CadenceTheme.primaryAccent : .secondary
                    )
                    .frame(width: 28, height: 28)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                isHovered ? CadenceTheme.hoverFill : CadenceTheme.subduedFill,
                in: RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusGroup,
                    style: .continuous
                )
            )
        }
        .buttonStyle(CadenceRowButtonStyle())
        .onHover { isHovered = $0 }
        .animation(
            .easeOut(duration: CadenceTheme.motionHover),
            value: isHovered
        )
        .accessibilityLabel("Play \(track.title) by \(track.artist)")
    }
}

struct HomeAlbumTile: View {
    @Bindable var model: CadenceAppModel
    let album: LibraryAlbumProjection
    @State private var isHovered = false

    var body: some View {
        Button {
            model.requestOpenProductionAlbumContextually(id: album.id)
        } label: {
            HStack(spacing: 12) {
                ProductionArtworkView(
                    model: model,
                    artworkID: album.customArtworkID,
                    title: album.title,
                    placeholder: .album,
                    cornerRadius: CadenceTheme.radiusControl
                )
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(album.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(album.artist.isEmpty ? "Album" : album.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                isHovered ? CadenceTheme.hoverFill : CadenceTheme.subduedFill,
                in: RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusGroup,
                    style: .continuous
                )
            )
        }
        .buttonStyle(CadenceRowButtonStyle())
        .onHover { isHovered = $0 }
        .animation(
            .easeOut(duration: CadenceTheme.motionHover),
            value: isHovered
        )
        .accessibilityLabel("Open \(album.title) by \(album.artist)")
    }
}

struct HomeDestinationTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(CadenceTheme.primaryAccent)
                    .frame(width: 56, height: 56)
                    .background(CadenceTheme.subduedFill, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                isHovered ? CadenceTheme.hoverFill : CadenceTheme.subduedFill,
                in: RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusGroup,
                    style: .continuous
                )
            )
        }
        .buttonStyle(CadenceRowButtonStyle())
        .onHover { isHovered = $0 }
        .animation(
            .easeOut(duration: CadenceTheme.motionHover),
            value: isHovered
        )
        .accessibilityLabel("Open \(title), \(subtitle)")
    }
}

struct HomeCompactGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 12),
            ],
            alignment: .leading,
            spacing: 12
        ) {
            content
        }
    }
}
