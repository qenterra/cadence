import AppKit
@testable import Cadence
import Foundation
import ImageIO
import Testing

@MainActor
struct MediaArtworkTests {
    @Test("Compact artwork data is downsampled to the thumbnail budget")
    func thumbnailBudget() throws {
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2048,
                pixelsHigh: 1024,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let source = try #require(
            representation.representation(using: .png, properties: [:])
        )
        let thumbnail = try #require(
            ArtworkThumbnailGenerator.data(
                from: source,
                maximumPixelDimension: 512
            )
        )
        let imageSource = try #require(
            CGImageSourceCreateWithData(thumbnail as CFData, nil)
        )
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
                as? [CFString: Any]
        )
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)

        #expect(max(width, height) == 512)
    }

    @Test("Artist artwork resolves custom image before placeholder")
    func artistPrecedence() {
        let asset = ArtworkAsset(data: Data([1]))

        #expect(
            ArtworkResolver.artist(custom: asset) == .custom(asset)
        )
        #expect(
            ArtworkResolver.artist(custom: nil) == .placeholder(.artist)
        )
    }

    @Test("Album artwork resolves custom, catalog, then placeholder")
    func albumPrecedence() {
        let asset = ArtworkAsset(data: Data([1]))

        #expect(
            ArtworkResolver.album(
                custom: asset,
                catalog: .ocean
            ) == .custom(asset)
        )
        #expect(
            ArtworkResolver.album(
                custom: nil,
                catalog: .ocean
            ) == .catalog(.ocean)
        )
        #expect(
            ArtworkResolver.album(
                custom: nil,
                catalog: nil
            ) == .placeholder(.album)
        )
    }

    @Test("Track inherits usable album artwork but not album placeholder")
    func trackPrecedence() {
        let trackAsset = ArtworkAsset(data: Data([1]))
        let albumAsset = ArtworkAsset(data: Data([2]))

        #expect(
            ArtworkResolver.track(
                custom: trackAsset,
                albumCustom: albumAsset,
                albumCatalog: .forest
            ) == .custom(trackAsset)
        )
        #expect(
            ArtworkResolver.track(
                custom: nil,
                albumCustom: albumAsset,
                albumCatalog: .forest
            ) == .custom(albumAsset)
        )
        #expect(
            ArtworkResolver.track(
                custom: nil,
                albumCustom: nil,
                albumCatalog: .forest
            ) == .catalog(.forest)
        )
        #expect(
            ArtworkResolver.track(
                custom: nil,
                albumCustom: nil,
                albumCatalog: nil
            ) == .placeholder(.track)
        )
    }

    @Test("Repository instances do not leak artwork state")
    func repositoryIsolation() {
        let first = InMemoryArtworkRepository()
        let second = InMemoryArtworkRepository()
        let target = ArtworkTarget.album("album")
        let asset = ArtworkAsset(data: Data([1]))

        first.setAsset(asset, for: target)

        #expect(first.asset(for: target) == asset)
        #expect(second.asset(for: target) == nil)
    }

    @Test("Replacing a crop preserves identity and increments revision")
    func revision() {
        let first = ArtworkAsset(data: Data([1]))
        let second = first.replacingCrop(
            data: Data([2]),
            scale: 2,
            normalizedOffset: CGSize(width: 0.1, height: -0.1)
        )

        #expect(second.id == first.id)
        #expect(second.revision == first.revision + 1)
        #expect(second.data == Data([2]))
    }

    @Test("Crop offsets include scaled-to-fill overflow at minimum zoom")
    func cropFillOverflow() {
        let portrait = ArtworkCropGeometry(
            previewSize: 340,
            sourceSize: CGSize(width: 100, height: 200)
        )
        let landscape = ArtworkCropGeometry(
            previewSize: 340,
            sourceSize: CGSize(width: 200, height: 100)
        )

        #expect(
            portrait.maximumOffset(scale: 1)
                == CGSize(width: 0, height: 170)
        )
        #expect(
            portrait.clamped(
                CGSize(width: 80, height: 250),
                scale: 1
            ) == CGSize(width: 0, height: 170)
        )
        #expect(
            landscape.maximumOffset(scale: 1)
                == CGSize(width: 170, height: 0)
        )
    }

    @Test("Crop zoom expands movable range on both axes")
    func cropZoomOverflow() {
        let square = ArtworkCropGeometry(
            previewSize: 340,
            sourceSize: CGSize(width: 100, height: 100)
        )

        #expect(
            square.maximumOffset(scale: 2)
                == CGSize(width: 170, height: 170)
        )
        #expect(
            square.clamped(
                CGSize(width: -220, height: 80),
                scale: 2
            ) == CGSize(width: -170, height: 80)
        )
    }

    @Test("Album overrides flow to tracks until a track override exists")
    func modelInheritance() throws {
        let model = CadenceAppModel.testFixture()
        let track = try #require(model.tracks.first)
        let album = try #require(
            model.albums.first { $0.id == track.albumID }
        )

        model.setCustomArtwork(
            data: Data([1]),
            scale: 1,
            normalizedOffset: .zero,
            for: .album(album.id)
        )
        let inherited = try #require(
            model.customArtwork(for: .album(album.id))
        )
        #expect(model.resolvedArtwork(for: track) == .custom(inherited))

        model.setCustomArtwork(
            data: Data([2]),
            scale: 2,
            normalizedOffset: .zero,
            for: .track(track.id)
        )
        let trackOverride = try #require(
            model.customArtwork(for: .track(track.id))
        )
        #expect(
            model.resolvedArtwork(for: track) == .custom(trackOverride)
        )

        model.removeCustomArtwork(for: .track(track.id))
        #expect(model.resolvedArtwork(for: track) == .custom(inherited))
    }

    @Test("Removing an album override restores catalog fallback")
    func removeFallback() throws {
        let model = CadenceAppModel.testFixture()
        let album = try #require(
            model.albums.first { $0.artworkPalette != nil }
        )
        let catalog = try #require(album.artworkPalette)

        model.setCustomArtwork(
            data: Data([1]),
            scale: 1,
            normalizedOffset: .zero,
            for: .album(album.id)
        )
        model.removeCustomArtwork(for: .album(album.id))

        #expect(model.resolvedArtwork(for: album) == .catalog(catalog))
    }
}
