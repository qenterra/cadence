import AppKit
import QenTerraDesignTokens
import QenTerraMediaComponents

enum CadenceTrackTableAdapter {
    static func presentation(for row: TrackRowDisplayProjection) -> MediaTableRowPresentation<UUID> {
        MediaTableRowPresentation(
            id: row.id, title: row.title, creator: row.artist, collection: row.album,
            year: row.year, duration: row.duration, isExplicit: row.isExplicit,
            isFavorite: row.isFavorite, isCurrent: row.isCurrentTrack, isPlaying: row.isPlaying,
            isAvailable: true, artworkIdentity: row.artworkRequest.artworkID?.uuidString,
            favoriteAccessibilityLabel: row.isFavorite
                ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"),
            actionsAccessibilityLabel: String(localized: "Track Actions")
        )
    }

    static func columns(_ columns: [TrackTableColumn]) -> [MediaTableColumn] {
        columns.map {
            switch $0 {
            case .album: .collection
            case .year: .year
            case .time: .duration
            }
        }
    }

    static func widths(_ widths: TrackTableResolvedWidths) -> MediaTableResolvedWidths {
        MediaTableResolvedWidths(title: widths.song, collection: widths.album, year: widths.year, duration: widths.time)
    }

    static func typography(_ size: InterfaceTextSize) -> MediaTableTypography {
        MediaTableTypography(
            primaryPointSize: size.nativePrimaryPointSize,
            secondaryPointSize: size.nativeSecondaryPointSize,
            badgeRole: DesignTokens.Typography.mediaExplicitBadge
        )
    }

    @MainActor static func environment(
        for view: NSView, density: TrackTableDensity, reduceMotion: Bool
    ) -> DesignNativeEnvironment {
        DesignNativeEnvironment(
            appearance: view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light,
            productProfile: .cadence,
            density: DesignDensity(rawValue: density.rawValue) ?? .standard,
            isIncreasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            reducesMotion: reduceMotion,
            reducesTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }

    static func action(_ action: NativeTrackTableAction) -> NativeMediaTableAction {
        switch action {
        case .select: .select
        case .play: .play
        case .favorite: .favorite
        case .artist: .creator
        case .album: .collection
        }
    }

    static func artworkContentsRect(asset: ArtworkAsset, image: CGImage) -> CGRect {
        let pixelWidth = CGFloat(image.width)
        let pixelHeight = CGFloat(image.height)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard pixelWidth > 0, pixelHeight > 0 else { return unit }
        let base: CGRect
        if pixelWidth > pixelHeight {
            let width = pixelHeight / pixelWidth
            base = CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        } else if pixelHeight > pixelWidth {
            let height = pixelWidth / pixelHeight
            base = CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        } else {
            base = unit
        }
        let zoom = max(asset.scale, 1)
        let size = CGSize(width: base.width / zoom, height: base.height / zoom)
        var origin = CGPoint(x: base.midX - size.width / 2, y: base.midY - size.height / 2)
        origin.x -= asset.normalizedOffset.width * size.width
        origin.y += asset.normalizedOffset.height * size.height
        origin.x = min(max(origin.x, base.minX), base.maxX - size.width)
        origin.y = min(max(origin.y, base.minY), base.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }
}

/// Coalesces native focus callbacks after the current responder change, as the coordinator expects.
@MainActor
final class CadenceTrackTableFocusDelivery {
    private var generation: UInt64 = 0

    func schedule(_ action: @escaping @MainActor () -> Void) {
        generation &+= 1
        let expected = generation
        DispatchQueue.main.async { [weak self] in
            guard self?.generation == expected else { return }
            action()
        }
    }
}
