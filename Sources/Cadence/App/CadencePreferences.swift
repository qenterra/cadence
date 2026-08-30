import Foundation

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
        static let showsTrackArtwork = "trackTable.showsArtwork"
        static let playbackTimeDisplay = "playback.timeDisplay"
        static let homeSectionOrder = "home.sectionOrder"
        static let hiddenHomeSections = "home.hiddenSections"
        static let restoresQueue = "playback.restoresQueue"
        static let previousTrackBehavior = "playback.previousBehavior"
        static let seekInterval = "playback.seekInterval"
        static let volumeNormalization = "playback.volumeNormalization"
        static let resumesAfterRouteRecovery =
            "playback.resumesAfterRouteRecovery"
        static let lyricsTextSize = "lyrics.textSize"
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

    private static let descriptors: [CadencePreferenceDescriptor] = [
        .string(
            Keys.appearance,
            default: CadenceAppearance.system.rawValue,
            allowed: Set(CadenceAppearance.allCases.map(\.rawValue))
        ),
        .string(
            Keys.catalogCardSize,
            default: CatalogCardSize.automatic.rawValue,
            allowed: Set(CatalogCardSize.allCases.map(\.rawValue))
        ),
        .bool(Keys.showsTrackArtwork, default: true),
        .string(
            Keys.playbackTimeDisplay,
            default: PlaybackTimeDisplayMode.elapsed.rawValue,
            allowed: Set(PlaybackTimeDisplayMode.allCases.map(\.rawValue))
        ),
        .string(Keys.homeSectionOrder, default: "pinned,favorites"),
        .string(Keys.hiddenHomeSections, default: ""),
        .bool(Keys.restoresQueue, default: true),
        .string(
            Keys.previousTrackBehavior,
            default: PreviousTrackBehavior.restartCurrent.rawValue,
            allowed: Set(PreviousTrackBehavior.allCases.map(\.rawValue))
        ),
        .integer(
            Keys.seekInterval,
            default: SeekInterval.seconds15.rawValue,
            allowed: Set(SeekInterval.allCases.map(\.rawValue))
        ),
        .string(
            Keys.volumeNormalization,
            default: VolumeNormalizationMode.off.rawValue,
            allowed: Set(VolumeNormalizationMode.allCases.map(\.rawValue))
        ),
        .bool(Keys.resumesAfterRouteRecovery, default: true),
        .string(
            Keys.lyricsTextSize,
            default: LyricsTextSize.standard.rawValue,
            allowed: Set(LyricsTextSize.allCases.map(\.rawValue))
        ),
        .bool("navigationRail.expanded", default: true),
        .string(
            "navigationRail.order",
            default: NavigationRailConfiguration.defaultOrderRawValue
        ),
        .string("navigationRail.hidden", default: ""),
        .bool(CadenceModePreferences.isEnabledKey, default: true),
        .bool(CadenceModePreferences.reactsToBassKey, default: true),
        .bool(CadenceModePreferences.showsLyricsKey, default: true),
        .bool(
            CadenceModePreferences.showsTrackInformationKey,
            default: true
        ),
        .bool(CadenceModePreferences.staysActiveKey, default: false),
        .bool(CadenceNotificationPreferences.trackChangesKey, default: false),
        .bool(
            CadenceNotificationPreferences.updateAvailabilityKey,
            default: false
        ),
        .bool("updates.includesBeta", default: false),
        .string("albums.sortField", default: AlbumSortField.artist.rawValue),
        .bool("albums.sortDescending", default: false),
        .string("artists.sortField", default: ArtistSortField.name.rawValue),
        .bool("artists.sortDescending", default: false),
        .string(
            "library.favoriteSection",
            default: FavoriteCatalogSection.songs.rawValue
        ),
        .string(
            "trackTable.visibleColumns",
            default: TrackTableColumn.defaultRawValue
        ),
        .integer("trackTable.columnDefaultsVersion", default: 0),
        .string(
            "trackTable.sortField",
            default: TrackTableSortField.song.rawValue
        ),
        .string(
            "trackTable.sortDirection",
            default: TrackTableSortDirection.ascending.rawValue
        ),
        .double("playlists.sidebarWidth", default: 270, range: 160 ... 720),
        .double("tags.sidebarWidth", default: 300, range: 160 ... 720),
        .double("tags.inspectorWidth", default: 330, range: 160 ... 720),
        .double("smartCollections.listWidth", default: 270, range: 160 ... 720),
        .double(
            "smartCollections.builderWidth",
            default: 430,
            range: 160 ... 720
        ),
    ]

    private static func repairedStringEnum<Value: RawRepresentable>(
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
}
