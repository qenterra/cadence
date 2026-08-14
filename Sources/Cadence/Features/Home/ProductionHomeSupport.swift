import SwiftUI

enum HomeTilePresentation: Equatable, Sendable {
    case artworkCard
    case textRow

    static func resolve(hasArtwork: Bool) -> Self {
        hasArtwork ? .artworkCard : .textRow
    }
}

enum HomeLayoutMetrics {
    static let minimumCardWidth: CGFloat = 176
    static let maximumCardWidth: CGFloat = 220
    static let artworkCardHeight: CGFloat = 264
    static let textRowHeight = CadenceLayout.comfortableRowHeight
    static let titleLineLimit = 2
    static let subtitleLineLimit = 1
}

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
        VStack(alignment: .leading, spacing: CadenceLayout.contentGap) {
            HStack(alignment: .bottom, spacing: CadenceLayout.contentGap) {
                VStack(alignment: .leading, spacing: CadenceLayout.textStack) {
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
                        HStack(spacing: CadenceLayout.textStack) {
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
                GridItem(
                    .adaptive(
                        minimum: HomeLayoutMetrics.minimumCardWidth,
                        maximum: HomeLayoutMetrics.maximumCardWidth
                    ),
                    spacing: CadenceLayout.contentGap
                ),
            ],
            alignment: .leading,
            spacing: CadenceLayout.contentGap
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
    var body: some View {
        HomeMediaTile(
            model: model,
            title: track.title,
            subtitle: track.artist,
            artworkID: track.artworkID,
            placeholder: .track,
            accessorySymbol: "play.fill",
            accessibilityLabel: "Play \(track.title) by \(track.artist)"
        ) {
            model.playProductionTrack(
                track,
                within: queue,
                source: queueSource
            )
        }
    }
}

struct HomeAlbumTile: View {
    @Bindable var model: CadenceAppModel
    let album: LibraryAlbumProjection
    var body: some View {
        HomeMediaTile(
            model: model,
            title: album.title,
            subtitle: album.artist.isEmpty ? "Album" : album.artist,
            artworkID: album.customArtworkID,
            placeholder: .album,
            accessorySymbol: "chevron.right",
            accessibilityLabel: "Open \(album.title) by \(album.artist)"
        ) {
            model.requestOpenProductionAlbumContextually(id: album.id)
        }
    }
}

struct HomeDestinationTile: View {
    @Bindable var model: CadenceAppModel
    let title: String
    let subtitle: String
    let artworkID: UUID?
    let placeholder: ArtworkPlaceholder
    let action: () -> Void

    var body: some View {
        HomeMediaTile(
            model: model,
            title: title,
            subtitle: subtitle,
            artworkID: artworkID,
            placeholder: placeholder,
            accessorySymbol: "chevron.right",
            accessibilityLabel: "Open \(title), \(subtitle)",
            action: action
        )
    }
}

private struct HomeMediaTile: View {
    @Bindable var model: CadenceAppModel
    let title: String
    let subtitle: String
    let artworkID: UUID?
    let placeholder: ArtworkPlaceholder
    let accessorySymbol: String
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void
    @State private var isHovered = false

    private var presentation: HomeTilePresentation {
        HomeTilePresentation.resolve(hasArtwork: artworkID != nil)
    }

    var body: some View {
        Button(action: action) {
            switch presentation {
            case .artworkCard:
                artworkCard
            case .textRow:
                textRow
            }
        }
        .buttonStyle(CadenceRowButtonStyle())
        .onHover { isHovered = $0 }
        .animation(
            .easeOut(duration: CadenceTheme.motionHover),
            value: isHovered
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var artworkCard: some View {
        VStack(alignment: .leading, spacing: CadenceLayout.compactGap) {
            ProductionArtworkView(
                model: model,
                artworkID: artworkID,
                title: title,
                placeholder: placeholder,
                cornerRadius: CadenceTheme.radiusGroup
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)

            labels
        }
        .padding(CadenceLayout.compactGap)
        .frame(
            maxWidth: .infinity,
            minHeight: HomeLayoutMetrics.artworkCardHeight,
            alignment: .topLeading
        )
        .background(
            isHovered ? CadenceTheme.hoverFill : .clear,
            in: RoundedRectangle(
                cornerRadius: CadenceTheme.radiusGroup,
                style: .continuous
            )
        )
    }

    private var textRow: some View {
        labels
            .padding(.horizontal, CadenceLayout.controlGap)
            .frame(
                maxWidth: .infinity,
                minHeight: HomeLayoutMetrics.textRowHeight,
                alignment: .leading
            )
            .background(
                isHovered ? CadenceTheme.hoverFill : CadenceTheme.subduedFill,
                in: RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusGroup,
                    style: .continuous
                )
            )
    }

    private var labels: some View {
        HStack(alignment: .top, spacing: CadenceLayout.compactGap) {
            VStack(alignment: .leading, spacing: CadenceLayout.textStack) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(HomeLayoutMetrics.titleLineLimit)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(HomeLayoutMetrics.subtitleLineLimit)
            }

            Spacer(minLength: CadenceLayout.textStack)

            Image(systemName: accessorySymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isHovered ? .primary : .tertiary)
                .frame(width: 24, height: 24)
        }
    }
}

struct HomeCompactGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: HomeLayoutMetrics.minimumCardWidth,
                        maximum: HomeLayoutMetrics.maximumCardWidth
                    ),
                    spacing: CadenceLayout.contentGap
                ),
            ],
            alignment: .leading,
            spacing: CadenceLayout.contentGap
        ) {
            content
        }
    }
}
