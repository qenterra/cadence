import Foundation
import SwiftUI

enum CatalogCardSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case small
    case medium
    case large

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}

enum PlaybackTimeDisplayMode: String, CaseIterable, Codable, Identifiable,
    Sendable {
    case elapsed
    case remaining

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .elapsed: String(localized: "Elapsed")
        case .remaining: String(localized: "Remaining")
        }
    }
}

enum PreviousTrackBehavior: String, CaseIterable, Codable, Identifiable,
    Sendable {
    case restartCurrent
    case alwaysPrevious

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .restartCurrent: String(localized: "Restart, Then Previous")
        case .alwaysPrevious: String(localized: "Always Previous Track")
        }
    }
}

enum SeekInterval: Int, CaseIterable, Codable, Identifiable, Sendable {
    case seconds5 = 5
    case seconds10 = 10
    case seconds15 = 15
    case seconds30 = 30

    var id: Self {
        self
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue)
    }

    var title: String {
        switch self {
        case .seconds5: String(localized: "5 seconds")
        case .seconds10: String(localized: "10 seconds")
        case .seconds15: String(localized: "15 seconds")
        case .seconds30: String(localized: "30 seconds")
        }
    }
}

enum VolumeNormalizationMode: String, CaseIterable, Codable, Identifiable,
    Sendable {
    case off
    case track

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .track: String(localized: "Track ReplayGain")
        }
    }
}

enum LyricsTextSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case small
    case standard
    case large

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .standard: String(localized: "Standard")
        case .large: String(localized: "Large")
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .small: 20
        case .standard: 24
        case .large: 28
        }
    }
}

enum CadencePreferences {
    enum Keys {
        static let appearance = "appearance"
        static let catalogCardSize = "catalog.cardSize"
        static let interfaceTextSize = "interface.textSize"
        static let startupPage = "navigation.startupPage"
        static let lastNavigationDestination = "navigation.lastDestination"
        static let showsTrackArtwork = "trackTable.showsArtwork"
        static let trackTableDensity = "trackTable.density"
        static let playbackTimeDisplay = "playback.timeDisplay"
        static let homeSectionOrder = "home.sectionOrder"
        static let hiddenHomeSections = "home.hiddenSections"
        static let restoresQueue = "playback.restoresQueue"
        static let previousTrackBehavior = "playback.previousBehavior"
        static let seekInterval = "playback.seekInterval"
        static let volumeNormalization = "playback.volumeNormalization"
        static let volumeAdjustmentStep = "playback.volumeAdjustmentStep"
        static let crossfadeDuration = "playback.crossfadeDuration"
        static let resumesAfterRouteRecovery =
            "playback.resumesAfterRouteRecovery"
        static let lyricsTextSize = "lyrics.textSize"
        static let showsTechnicalInformation = "nowPlaying.showsTechnicalInformation"
        static let preventsDisplaySleep = "playback.preventsDisplaySleep"
        static let listeningHistoryRetention = "library.listeningHistoryRetention"
        static let trashCleanupRetention = "library.trashCleanupRetention"
        static let playbackSession = "playback.session.v1"
    }

    static func registerDefaults(
        in defaults: UserDefaults = .standard
    ) {
        defaults.register(defaults: Dictionary(
            uniqueKeysWithValues: descriptors.map {
                ($0.key, $0.defaultValue.propertyListValue)
            }
        ))
    }

    static func catalogCardSize(
        in defaults: UserDefaults = .standard
    ) -> CatalogCardSize {
        repairedStringEnum(
            CatalogCardSize.self,
            key: Keys.catalogCardSize,
            fallback: .automatic,
            defaults: defaults
        )
    }

    static func playbackTimeDisplay(
        in defaults: UserDefaults = .standard
    ) -> PlaybackTimeDisplayMode {
        repairedStringEnum(
            PlaybackTimeDisplayMode.self,
            key: Keys.playbackTimeDisplay,
            fallback: .elapsed,
            defaults: defaults
        )
    }

    static func previousTrackBehavior(
        in defaults: UserDefaults = .standard
    ) -> PreviousTrackBehavior {
        repairedStringEnum(
            PreviousTrackBehavior.self,
            key: Keys.previousTrackBehavior,
            fallback: .restartCurrent,
            defaults: defaults
        )
    }

    static func seekInterval(
        in defaults: UserDefaults = .standard
    ) -> SeekInterval {
        let rawValue = defaults.object(forKey: Keys.seekInterval) as? Int
        guard let value = rawValue.flatMap(SeekInterval.init(rawValue:)) else {
            defaults.set(
                SeekInterval.seconds15.rawValue,
                forKey: Keys.seekInterval
            )
            return .seconds15
        }
        return value
    }

    static func volumeNormalization(
        in defaults: UserDefaults = .standard
    ) -> VolumeNormalizationMode {
        repairedStringEnum(
            VolumeNormalizationMode.self,
            key: Keys.volumeNormalization,
            fallback: .off,
            defaults: defaults
        )
    }

    static func lyricsTextSize(
        in defaults: UserDefaults = .standard
    ) -> LyricsTextSize {
        repairedStringEnum(
            LyricsTextSize.self,
            key: Keys.lyricsTextSize,
            fallback: .standard,
            defaults: defaults
        )
    }

    static var portableDescriptors: [CadencePreferenceDescriptor] {
        descriptors.filter(\.isPortable)
    }

    static var resettableDescriptors: [CadencePreferenceDescriptor] {
        descriptors.filter(\.isResettable)
    }

    static func repairedStringEnum<Value: RawRepresentable>(
        _: Value.Type,
        key: String,
        fallback: Value,
        defaults: UserDefaults
    ) -> Value where Value.RawValue == String {
        guard
            let rawValue = defaults.string(forKey: key),
            let value = Value(rawValue: rawValue)
        else {
            defaults.set(fallback.rawValue, forKey: key)
            return fallback
        }
        return value
    }

    static func repairedIntegerEnum<Value: RawRepresentable>(
        _: Value.Type,
        key: String,
        fallback: Value,
        defaults: UserDefaults
    ) -> Value where Value.RawValue == Int {
        let rawValue = defaults.object(forKey: key) as? Int
        guard let value = rawValue.flatMap(Value.init(rawValue:)) else {
            defaults.set(fallback.rawValue, forKey: key)
            return fallback
        }
        return value
    }
}
