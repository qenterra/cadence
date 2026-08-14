import Foundation

enum ArtworkTarget: Hashable, Sendable {
    case artist(ArtistPreview.ID)
    case album(AlbumPreview.ID)
    case track(TrackPreview.ID)
    case managedArtist(UUID)
    case managedAlbum(UUID)
    case managedTrack(UUID)
    case managedPlaylist(UUID)
    case managedSmartCollection(UUID)
}

enum ArtworkCropShape: Hashable, Sendable {
    case circle
    case square
}

struct ArtworkCropGeometry: Hashable, Sendable {
    let previewSize: CGFloat
    let sourceSize: CGSize

    func maximumOffset(scale: CGFloat) -> CGSize {
        guard
            previewSize.isFinite,
            previewSize > 0,
            sourceSize.width.isFinite,
            sourceSize.width > 0,
            sourceSize.height.isFinite,
            sourceSize.height > 0
        else {
            return .zero
        }

        let fillScale = max(
            previewSize / sourceSize.width,
            previewSize / sourceSize.height
        )
        let zoom = max(scale, 1)
        let renderedWidth = sourceSize.width * fillScale * zoom
        let renderedHeight = sourceSize.height * fillScale * zoom

        return CGSize(
            width: max((renderedWidth - previewSize) / 2, 0),
            height: max((renderedHeight - previewSize) / 2, 0)
        )
    }

    func clamped(
        _ proposedOffset: CGSize,
        scale: CGFloat
    ) -> CGSize {
        let maximumOffset = maximumOffset(scale: scale)
        return CGSize(
            width: min(
                max(proposedOffset.width, -maximumOffset.width),
                maximumOffset.width
            ),
            height: min(
                max(proposedOffset.height, -maximumOffset.height),
                maximumOffset.height
            )
        )
    }
}

enum ArtworkPlaceholder: String, Hashable, Sendable {
    case artist
    case album
    case track
    case playlist
    case smartCollection

    var symbolName: String {
        switch self {
        case .artist:
            "person.fill"
        case .album:
            "square.stack.fill"
        case .track:
            "music.note"
        case .playlist:
            "music.note.list"
        case .smartCollection:
            "sparkles.rectangle.stack"
        }
    }
}

enum ArtworkAssetVariant: Hashable, Sendable {
    case trackRow
    case thumbnail
    case original

    var maximumPixelDimension: Int? {
        switch self {
        case .trackRow: 128
        case .thumbnail: 512
        case .original: nil
        }
    }
}

struct ArtworkAsset: Identifiable, Hashable, @unchecked Sendable {
    let id: UUID
    let revision: Int
    let data: Data
    let variant: ArtworkAssetVariant
    let scale: CGFloat
    let normalizedOffset: CGSize

    init(
        id: UUID = UUID(),
        revision: Int = 0,
        data: Data,
        variant: ArtworkAssetVariant = .original,
        scale: CGFloat = 1,
        normalizedOffset: CGSize = .zero
    ) {
        self.id = id
        self.revision = max(revision, 0)
        self.data = data
        self.variant = variant
        self.scale = min(max(scale, 1), 4)
        self.normalizedOffset = normalizedOffset
    }

    func replacingCrop(
        data: Data,
        scale: CGFloat,
        normalizedOffset: CGSize
    ) -> Self {
        ArtworkAsset(
            id: id,
            revision: revision + 1,
            data: data,
            variant: .original,
            scale: scale,
            normalizedOffset: normalizedOffset
        )
    }
}

struct ArtworkCropDraft: Identifiable, Hashable, Sendable {
    let id = UUID()
    let target: ArtworkTarget
    let title: String
    let data: Data
    let shape: ArtworkCropShape
}

enum ResolvedArtworkSource: Hashable, Sendable {
    case custom(ArtworkAsset)
    case catalog(ArtworkPalette)
    case placeholder(ArtworkPlaceholder)
}

/// Owns user-selected artwork independently from catalog-derived placeholders.
///
/// Mutations are synchronous at this boundary so the presentation can update
/// atomically; durable implementations persist before returning.
@MainActor
protocol ArtworkRepository: AnyObject {
    func asset(for target: ArtworkTarget) -> ArtworkAsset?
    func setAsset(_ asset: ArtworkAsset, for target: ArtworkTarget)
    func removeAsset(for target: ArtworkTarget)
}

@MainActor
final class InMemoryArtworkRepository: ArtworkRepository {
    private var assets: [ArtworkTarget: ArtworkAsset] = [:]

    func asset(for target: ArtworkTarget) -> ArtworkAsset? {
        assets[target]
    }

    func setAsset(_ asset: ArtworkAsset, for target: ArtworkTarget) {
        assets[target] = asset
    }

    func removeAsset(for target: ArtworkTarget) {
        assets.removeValue(forKey: target)
    }
}

enum ArtworkResolver {
    static func artist(custom: ArtworkAsset?) -> ResolvedArtworkSource {
        custom.map(ResolvedArtworkSource.custom)
            ?? .placeholder(.artist)
    }

    static func album(
        custom: ArtworkAsset?,
        catalog: ArtworkPalette?
    ) -> ResolvedArtworkSource {
        if let custom {
            return .custom(custom)
        }
        if let catalog {
            return .catalog(catalog)
        }
        return .placeholder(.album)
    }

    static func track(
        custom: ArtworkAsset?,
        albumCustom: ArtworkAsset?,
        albumCatalog: ArtworkPalette?
    ) -> ResolvedArtworkSource {
        if let custom {
            return .custom(custom)
        }
        if let albumCustom {
            return .custom(albumCustom)
        }
        if let albumCatalog {
            return .catalog(albumCatalog)
        }
        return .placeholder(.track)
    }
}

typealias ArtistImageAsset = ArtworkAsset
