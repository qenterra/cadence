@testable import Cadence
import Foundation
import Testing

struct ProductLanguageTests {
    @Test("Now Playing summarizes audio quality before revealing diagnostics")
    func audioQualityProgressiveDisclosure() {
        let path = AudioPathSnapshot(
            codec: "flac",
            container: "flac",
            sourceBitDepth: 24,
            sourceSampleRate: 96000,
            sourceChannelCount: 2,
            sourceSpatialFormat: .stereo,
            backend: .pcm,
            rendererSampleRate: 96000,
            rendererChannelCount: 2,
            outputRoute: AudioRouteSnapshot(
                name: "MacBook Pro Speakers",
                transport: .builtIn
            ),
            nextTransitionIsGapless: true
        )

        let presentation = AudioQualityPresentation(path: path)

        #expect(presentation.badge == "FLAC · 24-bit · 96 kHz")
        #expect(presentation.details.map(\.label) == [
            "Format",
            "Channels",
            "Renderer",
            "Output",
            "Source",
            "Next Track",
        ])
        #expect(presentation.details[0].value == "FLAC · 24-bit · 96 kHz")
        #expect(presentation.details[2].value == "Cadence PCM · 96 kHz · Stereo")
        #expect(presentation.details.last?.value == "Gapless")
    }

    @Test("Track is the only catalog noun")
    func catalogTerminology() {
        #expect(FavoriteCatalogSection.songs.title == "Tracks")
        #expect(TrackTableSortField.song.title == "Track")
    }

    @Test("The legacy .library name never appears in product flows")
    func legacyPackageNameIsAbsentFromProductFlows() throws {
        let projectRoot = Self.projectRoot
        let productFlowFiles = [
            "Sources/Cadence/Features/ImportMusic",
            "Sources/Cadence/Features/SmartCollections",
        ]
        var violations: [String] = []

        for relativePath in productFlowFiles {
            let root = projectRoot.appending(path: relativePath)
            let files = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil
            )
            while let file = files?.nextObject() as? URL {
                guard file.pathExtension == "swift" else {
                    continue
                }
                let source = try String(contentsOf: file, encoding: .utf8)
                if source.contains("Cadence.library") {
                    violations.append(file.lastPathComponent)
                }
            }
        }

        #expect(violations.isEmpty)
    }

    @Test("Visible error titles use one conversational grammar")
    func errorTitleGrammar() throws {
        let roots = [
            "Sources/Cadence/Components",
            "Sources/Cadence/Features",
        ]
        var violations: [String] = []

        for relativePath in roots {
            let root = Self.projectRoot.appending(path: relativePath)
            let files = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil
            )
            while let file = files?.nextObject() as? URL {
                guard file.pathExtension == "swift" else {
                    continue
                }
                let source = try String(contentsOf: file, encoding: .utf8)
                if source.contains(" Could Not ")
                    || source.contains(" Failed\"") {
                    violations.append(file.lastPathComponent)
                }
            }
        }

        #expect(violations.isEmpty)
    }

    @Test("Error messages state the event, preserved state, and recovery")
    func errorMessageOrder() {
        let message = ProductErrorMessage(
            detail: "The source could not be read.",
            preservedState: "Nothing was imported.",
            recoveryAction: "Choose another folder or try again."
        )

        #expect(
            message.text == "The source could not be read.\n\n"
                + "Nothing was imported. Choose another folder or try again."
        )
    }

    @Test("Every localization key has a reviewed Russian value")
    func russianLocalizationParity() throws {
        let catalogURL = Self.projectRoot.appending(
            path: "Sources/Cadence/Resources/Localizable.xcstrings"
        )
        let data = try Data(contentsOf: catalogURL)
        let root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try #require(root["strings"] as? [String: Any])
        var missing: [String] = []
        var placeholderMismatches: [String] = []

        for (key, rawEntry) in strings where !key.isEmpty {
            guard
                let entry = rawEntry as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any],
                let russian = localizations["ru"] as? [String: Any],
                let unit = russian["stringUnit"] as? [String: Any],
                unit["state"] as? String == "translated",
                let value = unit["value"] as? String,
                !value.isEmpty
            else {
                missing.append(key)
                continue
            }

            if Self.placeholders(in: key) != Self.placeholders(in: value) {
                placeholderMismatches.append(key)
            }
        }

        #expect(missing.isEmpty)
        #expect(placeholderMismatches.isEmpty)
    }

    private static var projectRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func placeholders(in value: String) -> [String] {
        let expression = try? NSRegularExpression(
            pattern: #"%(?:\d+\$)?(?:@|lld)"#
        )
        let range = NSRange(value.startIndex..., in: value)
        return expression?.matches(in: value, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: value) else {
                return nil
            }
            return String(value[swiftRange])
                .replacingOccurrences(
                    of: #"%\d+\$"#,
                    with: "%",
                    options: .regularExpression
                )
        }.sorted() ?? []
    }
}
