import AppKit
@testable import Cadence
import SwiftData
import SwiftUI
import Testing

@MainActor
struct DocumentationScreenshotTests {
    @Test("Album capture cannot complete while album content is loading")
    func albumCaptureRequiresSemanticReadiness() async throws {
        let fixture = try await DocumentationScreenshotFixture.make()
        fixture.model.requestOpenProductionAlbumContextually(
            id: fixture.albumID
        )

        await #expect(throws: DocumentationScreenshotReadinessError.self) {
            try await fixture.waitUntilReady(
                for: .album(fixture.albumID),
                timeout: .milliseconds(50)
            )
        }
        try await fixture.cleanup()
    }

    @Test("A visual mismatch produces a deterministic diff artifact")
    func mismatchedBaselineProducesDiff() throws {
        let baseline = Self.imageURL("qa-home-min-dark.png")
        let actual = Self.imageURL("qa-empty-home-min-dark.png")
        let diff = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Screenshot-Diff-\(UUID().uuidString).png"
        )
        defer { try? FileManager.default.removeItem(at: diff) }

        #expect(throws: DocumentationScreenshotComparisonError.self) {
            try DocumentationScreenshotComparator.assertMatch(
                actual: actual,
                baseline: baseline,
                diff: diff
            )
        }
        #expect(FileManager.default.fileExists(atPath: diff.path))
    }

    @Test(
        "Render public screenshots from production projections",
        .appKitExclusive
    )
    func renderProductionScreenshots() async throws {
        let navigationPreferences = NavigationScreenshotPreferences()
        navigationPreferences.install()
        defer { navigationPreferences.restore() }

        let fixture = try await DocumentationScreenshotFixture.make()
        let homePreferences = HomeScreenshotPreferences(fixture: fixture)
        homePreferences.install()
        defer { homePreferences.restore() }

        fixture.model.selectedDestination = .home
        try await fixture.captureMatrix(prefix: "home")
        try await captureLongLocalizedHome()
        try await captureEmptyHome()

        fixture.model.selectedDestination = .library
        try await fixture.capture("cadence-library.png")
        try await fixture.captureMatrix(prefix: "library")

        fixture.model.selectedDestination = .allTracks
        try await fixture.capture("qa-all-tracks-min-dark.png")
        try await fixture.capture(
            "qa-all-tracks-wide-dark.png",
            contentSize: .wide
        )

        let nowPlayingFixture = try await DocumentationScreenshotFixture.make()
        nowPlayingFixture.model.presentNowPlaying()
        nowPlayingFixture.model.selectedNowPlayingPanel = .queue
        try await nowPlayingFixture.capture("cadence-now-playing.png")
        try await nowPlayingFixture.captureMatrix(prefix: "now-playing")

        let albumFixture = try await DocumentationScreenshotFixture.make()
        albumFixture.model.requestOpenProductionAlbumContextually(
            id: albumFixture.albumID
        )
        try await albumFixture.captureMatrix(prefix: "album")

        try await fixture.captureSettings("cadence-settings.png")
        try await fixture.captureSettingsMatrix()

        let importFixture = try await DocumentationScreenshotFixture.make()
        importFixture.model.selectedDestination = .importMusic
        importFixture.model.showImportPreviewStage(.review)
        try await importFixture.captureMatrix(prefix: "import-review")

        fixture.model.selectedDestination = .tags
        fixture.model.selectedProductionTagID = fixture.tagID
        try await fixture.capture("cadence-tags.png")

        try await importFixture.cleanup()
        try await albumFixture.cleanup()
        try await nowPlayingFixture.cleanup()
        try await fixture.cleanup()
    }

    private func captureEmptyHome() async throws {
        let fixture = try await DocumentationScreenshotFixture.makeEmpty()
        fixture.model.selectedDestination = .home
        for appearance in DocumentationScreenshotAppearance.allCases {
            try await fixture.capture(
                "qa-empty-home-min-\(appearance.slug).png",
                appearance: appearance
            )
        }
        try await fixture.cleanup()
    }

    private func captureLongLocalizedHome() async throws {
        let fixture = try await DocumentationScreenshotFixture.make()
        let preferences = HomeScreenshotPreferences(fixture: fixture)
        preferences.install()
        defer { preferences.restore() }

        fixture.installLongLocalizedHomeMetadata()
        fixture.model.selectedDestination = .home
        try await fixture.capture("qa-home-min-long-copy-dark.png")
        try await fixture.cleanup()
    }

    private static func imageURL(_ name: String) -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/images/\(name)")
    }
}
