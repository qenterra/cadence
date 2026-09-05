import Foundation

extension CadencePreferences {
    static let descriptors: [CadencePreferenceDescriptor] = [
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
        .string(
            Keys.interfaceTextSize,
            default: InterfaceTextSize.standard.rawValue,
            allowed: Set(InterfaceTextSize.allCases.map(\.rawValue))
        ),
        .string(
            Keys.startupPage,
            default: StartupPage.home.rawValue,
            allowed: Set(StartupPage.allCases.map(\.rawValue))
        ),
        .string(
            Keys.lastNavigationDestination,
            default: NavigationDestination.home.rawValue,
            allowed: Set(NavigationDestination.allCases.map(\.rawValue)),
            portable: false
        ),
        .bool(Keys.showsTrackArtwork, default: true),
        .string(
            Keys.trackTableDensity,
            default: TrackTableDensity.standard.rawValue,
            allowed: Set(TrackTableDensity.allCases.map(\.rawValue))
        ),
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
        .integer(
            Keys.volumeAdjustmentStep,
            default: VolumeAdjustmentStep.percent5.rawValue,
            allowed: Set(VolumeAdjustmentStep.allCases.map(\.rawValue))
        ),
        .integer(
            Keys.crossfadeDuration,
            default: CrossfadeDuration.off.rawValue,
            allowed: Set(CrossfadeDuration.allCases.map(\.rawValue))
        ),
        .bool(Keys.resumesAfterRouteRecovery, default: true),
        .string(
            Keys.lyricsTextSize,
            default: LyricsTextSize.standard.rawValue,
            allowed: Set(LyricsTextSize.allCases.map(\.rawValue))
        ),
        .bool(Keys.showsTechnicalInformation, default: true),
        .bool(Keys.preventsDisplaySleep, default: false),
        .integer(
            Keys.listeningHistoryRetention,
            default: ListeningHistoryRetention.forever.rawValue,
            allowed: Set(ListeningHistoryRetention.allCases.map(\.rawValue))
        ),
        .integer(
            Keys.trashCleanupRetention,
            default: TrashCleanupRetention.never.rawValue,
            allowed: Set(TrashCleanupRetention.allCases.map(\.rawValue))
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
        .bool(
            CadenceNotificationPreferences.foregroundBannersKey,
            default: true
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
}
