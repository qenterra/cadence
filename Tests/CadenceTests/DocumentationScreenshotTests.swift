import AppKit
@testable import Cadence
import SwiftData
import SwiftUI
import Testing

@MainActor
struct DocumentationScreenshotTests {
    @Test("Screenshot preferences cannot mutate the live navigation profile")
    func navigationPreferencesAreIsolated() {
        let key = "navigationRail.expanded"
        let liveDefaults = UserDefaults.standard
        let previousValue = liveDefaults.object(forKey: key)
        defer {
            if let previousValue {
                liveDefaults.set(previousValue, forKey: key)
            } else {
                liveDefaults.removeObject(forKey: key)
            }
        }

        liveDefaults.set(false, forKey: key)
        let preferences = NavigationScreenshotPreferences(isExpanded: true)
        preferences.install()
        defer { preferences.restore() }

        #expect(liveDefaults.bool(forKey: key) == false)
    }

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

@MainActor
struct CollapsedNavigationScreenshotTests {
    @Test(
        "Collapsed navigation preserves library and playback chrome",
        .appKitExclusive
    )
    func renderCollapsedNavigation() async throws {
        let navigationPreferences = NavigationScreenshotPreferences(
            isExpanded: false
        )
        navigationPreferences.install()
        defer { navigationPreferences.restore() }

        let libraryFixture = try await DocumentationScreenshotFixture.make()
        libraryFixture.model.selectedDestination = .library
        try await libraryFixture.capture(
            "qa-library-collapsed-min-dark.png"
        )

        let nowPlayingFixture = try await DocumentationScreenshotFixture.make()
        nowPlayingFixture.model.presentNowPlaying()
        try await nowPlayingFixture.capture(
            "qa-now-playing-collapsed-min-dark.png"
        )

        try await nowPlayingFixture.cleanup()
        try await libraryFixture.cleanup()
    }
}

@MainActor
struct AllTracksVisualAcceptanceTests {
    @Test(
        "All Tracks minimum viewport visual acceptance",
        .appKitExclusive
    )
    func renderMinimumViewport() async throws {
        try await render(
            "qa-all-tracks-min-dark.png",
            contentSize: .minimum
        )
    }

    @Test(
        "All Tracks wide viewport visual acceptance",
        .appKitExclusive
    )
    func renderWideViewport() async throws {
        try await render(
            "qa-all-tracks-wide-dark.png",
            contentSize: .wide
        )
    }

    private func render(
        _ filename: String,
        contentSize: NSSize
    ) async throws {
        let navigationPreferences = NavigationScreenshotPreferences()
        navigationPreferences.install()
        defer { navigationPreferences.restore() }

        let fixture = try await DocumentationScreenshotFixture.make()
        fixture.model.selectedDestination = .allTracks
        do {
            try await fixture.capture(filename, contentSize: contentSize)
        } catch {
            try? await fixture.cleanup()
            throw error
        }
        try await fixture.cleanup()
    }
}

@MainActor
struct SettingsVisualAcceptanceTests {
    @Test(
        "Settings keeps one stable strip across every tab and appearance",
        .appKitExclusive
    )
    func renderSettingsMatrix() async throws {
        #expect(
            CadenceSettingsTab.allCases.count
                * DocumentationScreenshotAppearance.allCases.count == 24
        )

        let fixture = try await DocumentationScreenshotFixture.make()
        do {
            try await fixture.captureSettingsMatrix(recordsOnly: true)
        } catch {
            try? await fixture.cleanup()
            throw error
        }
        try await fixture.cleanup()
    }
}
