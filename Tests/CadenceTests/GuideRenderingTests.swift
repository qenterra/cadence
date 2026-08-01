import AppKit
@testable import Cadence
import SwiftUI
import Testing

@MainActor
struct GuideRenderingTests {
    @Test("Welcome renders at its production sheet size")
    func welcomeRendering() throws {
        let coordinator = GuideCoordinator(
            progressStore: InMemoryGuideProgressStore()
        )
        let image = try render(
            CadenceWelcomeView(coordinator: coordinator),
            size: CGSize(width: 700, height: 520),
            name: "welcome"
        )

        #expect(image.size == CGSize(width: 700, height: 520))
        #expect(image.tiffRepresentation?.isEmpty == false)
    }

    @Test("Chapter picker renders every guide chapter")
    func chapterPickerRendering() throws {
        let coordinator = GuideCoordinator(
            progressStore: InMemoryGuideProgressStore()
        )
        coordinator.presentChapterPicker()
        let image = try render(
            GuideChapterPickerView(coordinator: coordinator),
            size: CGSize(width: 620, height: 570),
            name: "chapter-picker"
        )

        #expect(image.size == CGSize(width: 620, height: 570))
        #expect(GuideCatalog.allChapters.count == 6)
    }

    @Test("Guide fallback card renders without a target anchor")
    func fallbackOverlayRendering() throws {
        let coordinator = GuideCoordinator(
            progressStore: InMemoryGuideProgressStore()
        )
        coordinator.start(.playbackAndLyrics)
        coordinator.advance()
        let image = try render(
            CadenceGuideOverlay(
                coordinator: coordinator,
                anchors: [:],
                keyboardNavigationEnabled: false
            ),
            size: CGSize(width: 1512, height: 886),
            name: "fallback-overlay"
        )

        #expect(image.size == CGSize(width: 1512, height: 886))
        #expect(coordinator.currentStep?.anchor == .nowPlaying)
    }

    private func render(
        _ view: some View,
        size: CGSize,
        name: String
    ) throws -> NSImage {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        try writeCaptureIfRequested(image, name: name)
        return image
    }

    private func writeCaptureIfRequested(
        _ image: NSImage,
        name: String
    ) throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "cadence-guide-renders", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let tiffData = try #require(image.tiffRepresentation)
        let representation = try #require(NSBitmapImageRep(data: tiffData))
        let pngData = try #require(
            representation.representation(using: .png, properties: [:])
        )
        let outputURL = directoryURL.appending(path: "\(name).png")
        try pngData.write(to: outputURL, options: .atomic)
        print("CADENCE_GUIDE_RENDER: \(outputURL.path)")
    }
}
