import AppKit
@testable import Cadence
import Foundation

enum DocumentationScreenshotReadinessError: Error, LocalizedError {
    case timedOut(DocumentationScreenshotScene, diagnostic: String)

    var errorDescription: String? {
        switch self {
        case let .timedOut(scene, diagnostic):
            "Timed out before \(scene.name) reached its requested state: \(diagnostic)."
        }
    }
}

enum DocumentationScreenshotComparisonError: Error, LocalizedError {
    case missingBaseline(URL)
    case unreadableImage(URL)
    case sizeMismatch(URL)
    case pixelsDiffer(URL, Double, CGRect)

    var errorDescription: String? {
        switch self {
        case let .missingBaseline(url):
            "Screenshot baseline is missing at \(url.path)."
        case let .unreadableImage(url):
            "Screenshot image is unreadable at \(url.path)."
        case let .sizeMismatch(url):
            "Screenshot dimensions do not match the approved baseline at \(url.path)."
        case let .pixelsDiffer(url, fraction, bounds):
            "Screenshot \(url.lastPathComponent) differs by \(fraction * 100) percent in \(bounds)."
        }
    }
}

enum DocumentationScreenshotScene: Equatable {
    case home
    case library(NavigationDestination)
    case album(UUID)
    case nowPlaying
    case importReview
    case settings(CadenceSettingsTab)

    var name: String {
        switch self {
        case .home: "Home"
        case let .library(destination): "Library (\(destination))"
        case .album: "Album"
        case .nowPlaying: "Now Playing"
        case .importReview: "Import Review"
        case .settings: "Settings"
        }
    }
}

@MainActor
final class DocumentationScreenshotReadinessTracker {
    private var loadedAlbumIDs: Set<UUID> = []
    private var loadedAlbumTrackIDs: Set<UUID> = []
    private var renderedAlbumIDs: Set<UUID> = []
    private var renderedNowPlayingTrackIDs: Set<UUID> = []

    func didLoadAlbum(_ id: UUID) {
        loadedAlbumIDs.insert(id)
    }

    func didLoadAlbumTracks(_ id: UUID) {
        loadedAlbumTrackIDs.insert(id)
    }

    func didRenderAlbum(_ id: UUID) {
        renderedAlbumIDs.insert(id)
    }

    func didRenderNowPlaying(_ id: UUID) {
        renderedNowPlayingTrackIDs.insert(id)
    }

    func prepareForCapture(_ scene: DocumentationScreenshotScene) {
        if case let .album(id) = scene {
            renderedAlbumIDs.remove(id)
        }
        if case .nowPlaying = scene {
            renderedNowPlayingTrackIDs.removeAll()
        }
    }

    func isAlbumReady(_ id: UUID) -> Bool {
        loadedAlbumIDs.contains(id)
            && loadedAlbumTrackIDs.contains(id)
            && renderedAlbumIDs.contains(id)
    }

    func isNowPlayingReady(_ id: UUID) -> Bool {
        renderedNowPlayingTrackIDs.contains(id)
    }

    func albumDiagnostic(_ id: UUID) -> String {
        "album=\(loadedAlbumIDs.contains(id)), "
            + "tracks=\(loadedAlbumTrackIDs.contains(id)), "
            + "rendered=\(renderedAlbumIDs.contains(id))"
    }
}

enum DocumentationScreenshotComparator {
    static func assertMatch(
        actual: URL,
        baseline: URL,
        diff: URL,
        channelTolerance: UInt8 = 2,
        allowedPixelFraction: Double = 0.000_1
    ) throws {
        guard FileManager.default.fileExists(atPath: baseline.path) else {
            throw DocumentationScreenshotComparisonError.missingBaseline(
                baseline
            )
        }
        if try Data(contentsOf: actual) == Data(contentsOf: baseline) {
            try removeDiffIfPresent(diff)
            return
        }
        let actualPixels = try pixels(at: actual)
        let baselinePixels = try pixels(at: baseline)
        guard
            actualPixels.width == baselinePixels.width,
            actualPixels.height == baselinePixels.height
        else {
            throw DocumentationScreenshotComparisonError.sizeMismatch(
                baseline
            )
        }

        let mismatch = mismatchSummary(
            actualPixels,
            baselinePixels,
            channelTolerance: channelTolerance
        )
        let fraction = Double(mismatch.count)
            / Double(actualPixels.width * actualPixels.height)
        guard fraction <= allowedPixelFraction else {
            try writeDiff(
                makeDiff(
                    actualPixels,
                    baselinePixels,
                    channelTolerance: channelTolerance
                ),
                width: actualPixels.width,
                height: actualPixels.height,
                to: diff
            )
            throw DocumentationScreenshotComparisonError.pixelsDiffer(
                baseline,
                fraction,
                mismatch.bounds
            )
        }
        try removeDiffIfPresent(diff)
    }
}

private struct DocumentationScreenshotPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]
}

private extension DocumentationScreenshotComparator {
    static func pixels(at url: URL) throws -> DocumentationScreenshotPixels {
        guard
            let image = NSImage(contentsOf: url),
            let source = image.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
        else {
            throw DocumentationScreenshotComparisonError.unreadableImage(url)
        }
        let width = source.width
        let height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = bitmapContext(
            data: &bytes,
            width: width,
            height: height
        ) else {
            throw DocumentationScreenshotComparisonError.unreadableImage(url)
        }
        context.draw(
            source,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        return DocumentationScreenshotPixels(
            width: width,
            height: height,
            bytes: bytes
        )
    }

    static func mismatchSummary(
        _ actual: DocumentationScreenshotPixels,
        _ baseline: DocumentationScreenshotPixels,
        channelTolerance: UInt8
    ) -> (count: Int, bounds: CGRect) {
        var mismatchedPixels = 0
        var minimumX = actual.width
        var minimumY = actual.height
        var maximumX = 0
        var maximumY = 0
        let tolerance = Int(channelTolerance)
        var offset = 0
        while offset < actual.bytes.count {
            if pixelDiffers(
                actual.bytes,
                baseline.bytes,
                at: offset,
                tolerance: tolerance
            ) {
                mismatchedPixels += 1
                let pixel = offset / 4
                let column = pixel % actual.width
                let row = pixel / actual.width
                minimumX = min(minimumX, column)
                minimumY = min(minimumY, row)
                maximumX = max(maximumX, column)
                maximumY = max(maximumY, row)
            }
            offset += 4
        }
        let bounds = mismatchedPixels == 0
            ? .zero
            : CGRect(
                x: minimumX,
                y: minimumY,
                width: maximumX - minimumX + 1,
                height: maximumY - minimumY + 1
            )
        return (mismatchedPixels, bounds)
    }

    static func makeDiff(
        _ actual: DocumentationScreenshotPixels,
        _ baseline: DocumentationScreenshotPixels,
        channelTolerance: UInt8
    ) -> [UInt8] {
        var diff = baseline.bytes
        let tolerance = Int(channelTolerance)
        var offset = 0
        while offset < actual.bytes.count {
            if pixelDiffers(
                actual.bytes,
                baseline.bytes,
                at: offset,
                tolerance: tolerance
            ) {
                diff[offset] = 255
                diff[offset + 1] = 0
                diff[offset + 2] = 255
            } else {
                diff[offset] /= 4
                diff[offset + 1] /= 4
                diff[offset + 2] /= 4
            }
            diff[offset + 3] = 255
            offset += 4
        }
        return diff
    }

    static func pixelDiffers(
        _ actual: [UInt8],
        _ baseline: [UInt8],
        at offset: Int,
        tolerance: Int
    ) -> Bool {
        abs(Int(actual[offset]) - Int(baseline[offset])) > tolerance
            || abs(Int(actual[offset + 1]) - Int(baseline[offset + 1])) > tolerance
            || abs(Int(actual[offset + 2]) - Int(baseline[offset + 2])) > tolerance
            || abs(Int(actual[offset + 3]) - Int(baseline[offset + 3])) > tolerance
    }

    static func removeDiffIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func writeDiff(
        _ bytes: [UInt8],
        width: Int,
        height: Int,
        to url: URL
    ) throws {
        var bytes = bytes
        guard
            let context = bitmapContext(
                data: &bytes,
                width: width,
                height: height
            ),
            let image = context.makeImage()
        else {
            throw DocumentationScreenshotComparisonError.unreadableImage(url)
        }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw DocumentationScreenshotComparisonError.unreadableImage(url)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func bitmapContext(
        data: UnsafeMutableRawPointer,
        width: Int,
        height: Int
    ) -> CGContext? {
        CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }
}
