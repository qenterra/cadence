import SwiftUI

enum HomeTilePresentation: Equatable, Sendable {
    case artworkCard

    static func resolve(hasArtwork _: Bool) -> Self {
        .artworkCard
    }
}

enum HomeLayoutMetrics {
    static let artworkCardHeight: CGFloat = 236
    static let titleLineLimit = 2
    static let subtitleLineLimit = 1
}

enum HomeMediaTileAccessory {
    static func symbol(for kind: CatalogActivationKind) -> String? {
        kind == .track ? nil : "chevron.right"
    }
}

enum HomeListeningSelection {
    static func items<Item>(_ items: [Item], limit: Int) -> [Item] {
        Array(items.prefix(max(limit, 0)))
    }

    /// A higher-priority Home shelf owns an identity for that render pass.
    /// Lower shelves skip it instead of repeating the same shortcut or track.
    static func items<Item: Identifiable>(
        _ items: [Item],
        excludingIDs: Set<Item.ID>,
        limit: Int
    ) -> [Item] where Item.ID: Hashable {
        guard limit > 0 else {
            return []
        }
        return Array(
            items.lazy.filter { !excludingIDs.contains($0.id) }.prefix(limit)
        )
    }

    static func recentItems<Item: Identifiable>(
        _ items: [Item],
        limit: Int
    ) -> [Item] {
        guard limit > 0 else {
            return []
        }
        return Array(items.prefix(limit))
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
            columns: CatalogCardLayoutMetrics.layoutColumns(
                spacing: CadenceLayout.contentGap
            ),
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
            accessorySymbol: HomeMediaTileAccessory.symbol(for: .track),
            activationTarget: CatalogActivationTarget(
                kind: .track,
                id: track.id
            ),
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

struct HomeDestinationTile: View {
    @Bindable var model: CadenceAppModel
    let title: String
    let subtitle: String
    let artworkID: UUID?
    let placeholder: ArtworkPlaceholder
    let activationTarget: CatalogActivationTarget
    let action: () -> Void

    var body: some View {
        HomeMediaTile(
            model: model,
            title: title,
            subtitle: subtitle,
            artworkID: artworkID,
            placeholder: placeholder,
            accessorySymbol: HomeMediaTileAccessory.symbol(
                for: activationTarget.kind
            ),
            activationTarget: activationTarget,
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
    let accessorySymbol: String?
    let activationTarget: CatalogActivationTarget
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            guard model.requestCatalogActivation(activationTarget) else {
                return
            }
            action()
        } label: {
            artworkCard
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
        .frame(width: CatalogCardLayoutMetrics.cardWidth)
        .frame(
            minHeight: HomeLayoutMetrics.artworkCardHeight,
            alignment: .topLeading
        )
        .background(
            model.catalogActivationSelection.selected == activationTarget
                ? CadenceTheme.selectionFill
                : (isHovered ? CadenceTheme.hoverFill : .clear),
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

            if let accessorySymbol {
                Image(systemName: accessorySymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isHovered ? .primary : .tertiary)
                    .frame(width: 24, height: 24)
            }
        }
    }
}

struct HomeCompactGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: CatalogCardLayoutMetrics.layoutColumns(
                spacing: CadenceLayout.contentGap
            ),
            alignment: .leading,
            spacing: CadenceLayout.contentGap
        ) {
            content
        }
    }
}
