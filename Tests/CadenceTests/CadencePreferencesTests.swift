@testable import Cadence
import Foundation
import Testing

@MainActor
struct CadencePreferencesTests {
    @Test("Customization preferences expose stable product defaults")
    func stableDefaults() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        CadencePreferences.registerDefaults(in: defaults)

        #expect(CadencePreferences.catalogCardSize(in: defaults) == .automatic)
        #expect(defaults.bool(forKey: CadencePreferences.Keys.showsTrackArtwork))
        #expect(CadencePreferences.playbackTimeDisplay(in: defaults) == .elapsed)
        #expect(CadencePreferences.previousTrackBehavior(in: defaults) == .restartCurrent)
        #expect(CadencePreferences.seekInterval(in: defaults) == .seconds15)
        #expect(CadencePreferences.volumeNormalization(in: defaults) == .off)
        #expect(CadencePreferences.lyricsTextSize(in: defaults) == .standard)
        #expect(defaults.bool(forKey: CadencePreferences.Keys.restoresQueue))
        #expect(defaults.bool(forKey: CadencePreferences.Keys.resumesAfterRouteRecovery))
    }

    @Test("Invalid typed values repair to their declared defaults")
    func invalidTypedValuesRepair() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("wall-sized", forKey: CadencePreferences.Keys.catalogCardSize)
        defaults.set("tomorrow", forKey: CadencePreferences.Keys.playbackTimeDisplay)
        defaults.set(13, forKey: CadencePreferences.Keys.seekInterval)

        #expect(CadencePreferences.catalogCardSize(in: defaults) == .automatic)
        #expect(CadencePreferences.playbackTimeDisplay(in: defaults) == .elapsed)
        #expect(CadencePreferences.seekInterval(in: defaults) == .seconds15)
        #expect(
            defaults.string(forKey: CadencePreferences.Keys.catalogCardSize)
                == CatalogCardSize.automatic.rawValue
        )
        #expect(
            defaults.integer(forKey: CadencePreferences.Keys.seekInterval)
                == SeekInterval.seconds15.rawValue
        )
    }

    @Test("Portable profile includes customization but excludes private runtime state")
    func portableProfileAllowlist() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        CadencePreferences.registerDefaults(in: defaults)

        defaults.set(
            CatalogCardSize.large.rawValue,
            forKey: CadencePreferences.Keys.catalogCardSize
        )
        defaults.set(false, forKey: CadencePreferences.Keys.showsTrackArtwork)
        defaults.set(Data([0x01]), forKey: "remoteLibrary.settings.v1")
        defaults.set(Data([0x02]), forKey: CadencePreferences.Keys.playbackSession)
        defaults.set("secret", forKey: "managedLibrary.locationBookmark")
        defaults.set("1.2.3", forKey: CadenceNotificationPreferences.lastUpdateVersionKey)

        let profile = CadenceSettingsProfileService(defaults: defaults).makeProfile()

        #expect(
            profile.preferences[CadencePreferences.Keys.catalogCardSize]
                == .string(CatalogCardSize.large.rawValue)
        )
        #expect(
            profile.preferences[CadencePreferences.Keys.showsTrackArtwork]
                == .bool(false)
        )
        #expect(profile.preferences["remoteLibrary.settings.v1"] == nil)
        #expect(profile.preferences[CadencePreferences.Keys.playbackSession] == nil)
        #expect(profile.preferences["managedLibrary.locationBookmark"] == nil)
        #expect(
            profile.preferences[CadenceNotificationPreferences.lastUpdateVersionKey]
                == nil
        )
    }

    @Test("Import validates the whole profile before changing preferences")
    func importIsAtomic() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        CadencePreferences.registerDefaults(in: defaults)
        defaults.set(
            CadenceAppearance.dark.rawValue,
            forKey: CadencePreferences.Keys.appearance
        )
        defaults.set(
            CatalogCardSize.small.rawValue,
            forKey: CadencePreferences.Keys.catalogCardSize
        )
        let service = CadenceSettingsProfileService(defaults: defaults)
        let invalid = CadenceSettingsProfile(
            schemaVersion: CadenceSettingsProfile.currentSchemaVersion,
            preferences: [
                CadencePreferences.Keys.appearance: .string(
                    CadenceAppearance.light.rawValue
                ),
                CadencePreferences.Keys.catalogCardSize: .integer(12),
            ]
        )

        #expect(throws: CadenceSettingsProfileError.self) {
            try service.importProfile(invalid)
        }
        #expect(
            defaults.string(forKey: CadencePreferences.Keys.appearance)
                == CadenceAppearance.dark.rawValue
        )
        #expect(
            defaults.string(forKey: CadencePreferences.Keys.catalogCardSize)
                == CatalogCardSize.small.rawValue
        )
    }

    @Test("Unsupported profile schemas are rejected")
    func unsupportedSchema() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = CadenceSettingsProfileService(defaults: defaults)
        let future = CadenceSettingsProfile(
            schemaVersion: CadenceSettingsProfile.currentSchemaVersion + 1,
            preferences: [:]
        )

        #expect(throws: CadenceSettingsProfileError.self) {
            try service.importProfile(future)
        }
    }

    @Test("Customization reset preserves the library, remote connection, and queue session")
    func resetPreservesNonCustomizationState() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        CadencePreferences.registerDefaults(in: defaults)
        defaults.set(
            CatalogCardSize.large.rawValue,
            forKey: CadencePreferences.Keys.catalogCardSize
        )
        defaults.set(Data([0x01]), forKey: "remoteLibrary.settings.v1")
        defaults.set(Data([0x02]), forKey: CadencePreferences.Keys.playbackSession)
        defaults.set("bookmark", forKey: "managedLibrary.locationBookmark")

        CadenceSettingsProfileService(defaults: defaults).resetCustomization()

        #expect(CadencePreferences.catalogCardSize(in: defaults) == .automatic)
        #expect(defaults.data(forKey: "remoteLibrary.settings.v1") == Data([0x01]))
        #expect(
            defaults.data(forKey: CadencePreferences.Keys.playbackSession)
                == Data([0x02])
        )
        #expect(defaults.string(forKey: "managedLibrary.locationBookmark") == "bookmark")
    }

    @Test("Every catalog card size maps to one ordered responsive range")
    func catalogCardRanges() {
        let small = CatalogCardLayoutMetrics.widthRange(for: .small)
        let automatic = CatalogCardLayoutMetrics.widthRange(for: .automatic)
        let medium = CatalogCardLayoutMetrics.widthRange(for: .medium)
        let large = CatalogCardLayoutMetrics.widthRange(for: .large)

        #expect(small.upperBound < automatic.lowerBound)
        #expect(automatic == 164 ... 196)
        #expect(automatic.upperBound < medium.upperBound)
        #expect(medium.upperBound < large.upperBound)
    }

    @Test("Track artwork visibility reclaims the complete artwork slot")
    func hiddenArtworkReclaimsItsSlot() {
        let shown = NativeTrackRowHorizontalGeometry(
            rowHeight: 58,
            leadingX: 72,
            showsArtwork: true
        )
        let hidden = NativeTrackRowHorizontalGeometry(
            rowHeight: 58,
            leadingX: 72,
            showsArtwork: false
        )

        #expect(shown.artworkFrame != nil)
        #expect(hidden.artworkFrame == nil)
        #expect(hidden.songOriginX == 72)
        #expect(shown.songOriginX - hidden.songOriginX == 48)
    }

    @Test("Playback time preference formats elapsed or remaining time")
    func playbackTimePresentation() {
        #expect(
            PlaybackTimePresentation.leadingText(
                mode: .elapsed,
                currentTime: 42,
                duration: 210
            ) == "0:42"
        )
        #expect(
            PlaybackTimePresentation.leadingText(
                mode: .remaining,
                currentTime: 42,
                duration: 210
            ) == "−2:48"
        )
        #expect(
            PlaybackTimePresentation.leadingText(
                mode: .remaining,
                currentTime: 400,
                duration: 210
            ) == "−0:00"
        )
    }

    @Test("Lyrics sizes preserve an ordered semantic scale")
    func lyricsTextScale() {
        #expect(LyricsTextSize.small.pointSize < LyricsTextSize.standard.pointSize)
        #expect(LyricsTextSize.standard.pointSize < LyricsTextSize.large.pointSize)
        #expect(LyricsTextSize.standard.pointSize == 24)
    }

    @Test("Home configuration keeps Recently Played first and repairs stored order")
    func homeSectionConfiguration() {
        #expect(
            HomeSectionConfiguration.orderedConfigurableSections(
                from: "favorites,unknown,favorites"
            ) == [.favorites, .pinned]
        )
        #expect(
            HomeSectionConfiguration.visibleSections(
                orderRawValue: "favorites,pinned",
                hiddenRawValue: "pinned"
            ) == [.recentlyPlayed, .favorites]
        )
    }

    @Test("Sidebar reset restores order, visibility, and expanded state")
    func sidebarReset() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("albums,home", forKey: "navigationRail.order")
        defaults.set("home", forKey: "navigationRail.hidden")
        defaults.set(false, forKey: "navigationRail.expanded")

        NavigationRailConfiguration.reset(in: defaults)

        #expect(
            defaults.string(forKey: "navigationRail.order")
                == NavigationRailConfiguration.defaultOrderRawValue
        )
        #expect(defaults.string(forKey: "navigationRail.hidden") == "")
        #expect(defaults.bool(forKey: "navigationRail.expanded"))
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "CadencePreferencesTests-\(UUID().uuidString)"
        return try (#require(UserDefaults(suiteName: suite)), suite)
    }
}
