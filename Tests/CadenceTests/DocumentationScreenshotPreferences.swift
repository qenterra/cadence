import AppKit
@testable import Cadence
import Foundation
import SwiftData
import SwiftUI
import Testing

@MainActor
enum DocumentationScreenshotDefaults {
    static let userDefaults = UserDefaults(
        suiteName: "com.qenterra.cadence.visual-regression"
    )!
}

extension LibraryTrackProjection {
    func replacingHomeMetadata(
        title: String,
        artist: String
    ) -> LibraryTrackProjection {
        LibraryTrackProjection(
            id: id,
            title: title,
            artistID: artistID,
            artist: artist,
            albumID: albumID,
            album: album,
            duration: duration,
            year: year,
            codec: codec,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitDepth: bitDepth,
            isFavorite: isFavorite,
            isExplicit: isExplicit,
            customArtworkID: customArtworkID,
            artworkID: artworkID,
            relativeMediaPath: relativeMediaPath,
            lastPlayedAt: lastPlayedAt,
            hasSynchronizedLyrics: hasSynchronizedLyrics
        )
    }
}

final class HomeScreenshotPreferences {
    private let defaults = UserDefaults.standard
    private let values: [String: [String]]
    private let previousValues: [String: Any]

    init(fixture: DocumentationScreenshotFixture) {
        let values = [
            HomePinKind.album.storageKey: [fixture.albumID.uuidString],
            HomePinKind.artist.storageKey: [fixture.artistID.uuidString],
        ]
        let defaults = UserDefaults.standard
        self.values = values
        previousValues = values.keys.reduce(into: [:]) { result, key in
            result[key] = defaults.object(forKey: key)
        }
    }

    func install() {
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        defaults.set(
            defaults.integer(forKey: "home.pins.revision") + 1,
            forKey: "home.pins.revision"
        )
    }

    func restore() {
        for key in values.keys {
            if let value = previousValues[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

/// Isolates captures from navigation preferences mutated by other test suites.
@MainActor
final class NavigationScreenshotPreferences {
    private let defaults = DocumentationScreenshotDefaults.userDefaults
    private let values: [String: Any]
    private let previousValues: [String: Any]

    init(isExpanded: Bool = true) {
        values = [
            "navigationRail.expanded": isExpanded,
            "navigationRail.order": NavigationRailConfiguration.defaultOrderRawValue,
            "navigationRail.hidden": "",
            "trackTable.visibleColumns": TrackTableColumn.defaultRawValue,
            "trackTable.columnDefaultsVersion": 2,
            "trackTable.sortField": TrackTableSortField.song.rawValue,
            "trackTable.sortDirection": TrackTableSortDirection.ascending.rawValue,
            "trackTable.songWidth": TrackTableWidth.song.defaultValue,
            "trackTable.albumWidth": TrackTableWidth.album.defaultValue,
            "trackTable.yearWidth": TrackTableWidth.year.defaultValue,
            "trackTable.timeWidth": TrackTableWidth.time.defaultValue,
            "tags.sidebarWidth": 300.0,
            "tags.inspectorWidth": 330.0,
        ]
        let keys = [
            "navigationRail.expanded",
            "navigationRail.order",
            "navigationRail.hidden",
            "trackTable.visibleColumns",
            "trackTable.columnDefaultsVersion",
            "trackTable.sortField",
            "trackTable.sortDirection",
            "trackTable.songWidth",
            "trackTable.albumWidth",
            "trackTable.yearWidth",
            "trackTable.timeWidth",
            "tags.sidebarWidth",
            "tags.inspectorWidth",
        ]
        let screenshotDefaults = DocumentationScreenshotDefaults.userDefaults
        previousValues = keys.reduce(into: [:]) { result, key in
            result[key] = screenshotDefaults.object(forKey: key)
        }
    }

    func install() {
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
    }

    func restore() {
        for key in values.keys {
            if let value = previousValues[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

enum DocumentationScreenshotError: Error {
    case captureUnavailable
    case encodingFailed
}
