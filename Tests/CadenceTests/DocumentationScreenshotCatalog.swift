@testable import Cadence
import Foundation
import Testing

// Keeping each screenshot identity on one line makes filename, scene, viewport,
// and appearance drift reviewable as a single catalog entry.
// swiftlint:disable line_length

struct DocumentationScreenshotCatalogEntry: Codable, Equatable, Hashable, Sendable {
    let filename: String
    let scene: String
    let viewport: String
    let appearance: String
}

enum DocumentationScreenshotCatalog {
    static let appearances = ["system", "light", "dark"]
    static let viewports = ["min", "ideal", "wide"]
    static let matrixScenes = ["home", "library", "album", "now-playing", "import-review"]
    static let settingsTabs = [
        "general", "playback", "library", "interface",
        "shortcuts", "updates", "advanced", "about",
    ]

    static let topLevelDestinations = NavigationDestination.allCases.map(\.rawValue)

    static let entries: [DocumentationScreenshotCatalogEntry] = {
        var result: [DocumentationScreenshotCatalogEntry] = []

        for scene in matrixScenes {
            for viewport in viewports {
                for appearance in appearances {
                    result.append(
                        .init(
                            filename: "qa-\(scene)-\(viewport)-\(appearance).png",
                            scene: scene,
                            viewport: viewport,
                            appearance: appearance
                        )
                    )
                }
            }
        }

        for appearance in appearances {
            result.append(
                .init(
                    filename: "qa-empty-home-min-\(appearance).png",
                    scene: "empty-home",
                    viewport: "min",
                    appearance: appearance
                )
            )
            for tab in settingsTabs {
                result.append(
                    .init(
                        filename: "qa-settings-\(tab)-\(appearance).png",
                        scene: "settings-\(tab)",
                        viewport: "settings",
                        appearance: appearance
                    )
                )
            }
        }

        result.append(contentsOf: [
            .init(filename: "cadence-library.png", scene: "library", viewport: "min", appearance: "dark"),
            .init(filename: "cadence-now-playing.png", scene: "now-playing", viewport: "min", appearance: "dark"),
            .init(filename: "cadence-settings.png", scene: "settings-general", viewport: "settings", appearance: "dark"),
            .init(filename: "cadence-tags.png", scene: "tags", viewport: "min", appearance: "dark"),
            .init(filename: "qa-all-tracks-min-dark.png", scene: "all-tracks", viewport: "min", appearance: "dark"),
            .init(filename: "qa-all-tracks-wide-dark.png", scene: "all-tracks", viewport: "wide", appearance: "dark"),
            .init(filename: "qa-home-min-long-copy-dark.png", scene: "home-long-copy", viewport: "min", appearance: "dark"),
            .init(filename: "qa-library-collapsed-min-dark.png", scene: "library-collapsed", viewport: "min", appearance: "dark"),
            .init(filename: "qa-now-playing-collapsed-min-dark.png", scene: "now-playing-collapsed", viewport: "min", appearance: "dark"),
            .init(filename: "qa-page-playlists-empty-ideal-dark.png", scene: "page-playlists-empty", viewport: "ideal", appearance: "dark"),
            .init(filename: "qa-cadence-mode-standard-min-dark.png", scene: "cadence-mode-standard", viewport: "min", appearance: "dark"),
            .init(filename: "qa-cadence-mode-standard-min-light.png", scene: "cadence-mode-standard", viewport: "min", appearance: "light"),
            .init(filename: "qa-cadence-mode-min-dark.png", scene: "cadence-mode", viewport: "min", appearance: "dark"),
            .init(filename: "qa-cadence-mode-min-light.png", scene: "cadence-mode", viewport: "min", appearance: "light"),
            .init(filename: "qa-cadence-mode-wide-dark.png", scene: "cadence-mode", viewport: "wide", appearance: "dark"),
            .init(filename: "qa-cadence-mode-wide-light.png", scene: "cadence-mode", viewport: "wide", appearance: "light"),
            .init(filename: "qa-cadence-mode-large-dark.png", scene: "cadence-mode", viewport: "large", appearance: "dark"),
            .init(filename: "qa-cadence-mode-grayscale-min-dark.png", scene: "cadence-mode-grayscale", viewport: "min", appearance: "dark"),
            .init(filename: "qa-cadence-mode-wide-transition-mid-dark.png", scene: "cadence-mode-transition-mid", viewport: "wide", appearance: "dark"),
            .init(filename: "qa-cadence-mode-wide-transition-settled-dark.png", scene: "cadence-mode-transition-settled", viewport: "wide", appearance: "dark"),
            .init(filename: "qa-detail-artist-ideal-dark.png", scene: "detail-artist", viewport: "ideal", appearance: "dark"),
            .init(filename: "qa-now-playing-tag-entry-ideal-dark.png", scene: "now-playing-tag-entry", viewport: "ideal", appearance: "dark"),
            .init(filename: "qa-smart-collection-editor-invalid-ideal-dark.png", scene: "smart-collection-editor-invalid", viewport: "ideal", appearance: "dark"),
            .init(filename: "qa-smart-collection-editor-valid-ideal-dark.png", scene: "smart-collection-editor-valid", viewport: "ideal", appearance: "dark"),
        ])

        result.append(contentsOf: topLevelDestinations.map {
            .init(
                filename: "qa-page-\($0)-ideal-dark.png",
                scene: "page-\($0)",
                viewport: "ideal",
                appearance: "dark"
            )
        })
        return result.sorted { $0.filename < $1.filename }
    }()

    static let expectedFilenames = entries.map(\.filename)

    static var manifestURL: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "scripts/documentation-screenshot-manifest.json")
    }
}

@MainActor
struct DocumentationScreenshotCatalogTests {
    @Test("The screenshot catalog names every top-level destination and has unique outputs")
    func catalogCoversEveryTopLevelDestination() {
        #expect(Set(DocumentationScreenshotCatalog.expectedFilenames).count == DocumentationScreenshotCatalog.entries.count)
        for destination in NavigationDestination.allCases {
            #expect(
                DocumentationScreenshotCatalog.expectedFilenames.contains(
                    "qa-page-\(destination.rawValue)-ideal-dark.png"
                )
            )
        }
        #expect(Set(DocumentationScreenshotCatalog.appearances) == Set(["system", "light", "dark"]))
        #expect(Set(DocumentationScreenshotCatalog.viewports) == Set(["min", "ideal", "wide"]))
    }

    @Test("The JSON screenshot manifest exactly matches the Swift catalog")
    func manifestMatchesCatalog() throws {
        let data = try Data(contentsOf: DocumentationScreenshotCatalog.manifestURL)
        let manifest = try JSONDecoder().decode(
            DocumentationScreenshotManifest.self,
            from: data
        )
        #expect(manifest.files == DocumentationScreenshotCatalog.expectedFilenames)
    }
}

private struct DocumentationScreenshotManifest: Decodable {
    let files: [String]
}

// swiftlint:enable line_length
