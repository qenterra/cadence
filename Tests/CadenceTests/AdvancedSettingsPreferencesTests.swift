@testable import Cadence
import Foundation
import Testing

@MainActor
struct AdvancedSettingsPreferencesTests {
    @Test("Advanced settings have safe product defaults and repair invalid values")
    func defaultsAndRepair() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        CadencePreferences.registerDefaults(in: defaults)

        #expect(CadencePreferences.interfaceTextSize(in: defaults) == .standard)
        #expect(CadencePreferences.trackTableDensity(in: defaults) == .standard)
        #expect(CadencePreferences.startupPage(in: defaults) == .home)
        #expect(CadencePreferences.volumeAdjustmentStep(in: defaults) == .percent5)
        #expect(CadencePreferences.crossfadeDuration(in: defaults) == .off)
        #expect(CadencePreferences.listeningHistoryRetention(in: defaults) == .forever)
        #expect(CadencePreferences.trashCleanupRetention(in: defaults) == .never)
        #expect(defaults.bool(forKey: CadencePreferences.Keys.showsTechnicalInformation))
        #expect(!defaults.bool(forKey: CadencePreferences.Keys.preventsDisplaySleep))
        #expect(defaults.bool(forKey: CadenceNotificationPreferences.foregroundBannersKey))

        defaults.set("microscopic", forKey: CadencePreferences.Keys.interfaceTextSize)
        defaults.set("crushed", forKey: CadencePreferences.Keys.trackTableDensity)
        defaults.set("lyrics", forKey: CadencePreferences.Keys.startupPage)
        defaults.set(7, forKey: CadencePreferences.Keys.volumeAdjustmentStep)
        defaults.set(5, forKey: CadencePreferences.Keys.crossfadeDuration)

        #expect(CadencePreferences.interfaceTextSize(in: defaults) == .standard)
        #expect(CadencePreferences.trackTableDensity(in: defaults) == .standard)
        #expect(CadencePreferences.startupPage(in: defaults) == .home)
        #expect(CadencePreferences.volumeAdjustmentStep(in: defaults) == .percent5)
        #expect(CadencePreferences.crossfadeDuration(in: defaults) == .off)
    }

    @Test("Portable profiles include user choices but exclude navigation runtime state")
    func portableProfileBoundary() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        CadencePreferences.registerDefaults(in: defaults)
        defaults.set(
            NavigationDestination.albums.rawValue,
            forKey: CadencePreferences.Keys.lastNavigationDestination
        )
        defaults.set(
            InterfaceTextSize.large.rawValue,
            forKey: CadencePreferences.Keys.interfaceTextSize
        )

        let profile = CadenceSettingsProfileService(defaults: defaults)
            .makeProfile()

        #expect(
            profile.preferences[CadencePreferences.Keys.lastNavigationDestination]
                == nil
        )
        #expect(
            profile.preferences[CadencePreferences.Keys.interfaceTextSize]
                == .string(InterfaceTextSize.large.rawValue)
        )
    }

    @Test("Interface text sizes and track densities stay ordered")
    func interfaceScaleAndDensity() {
        #expect(InterfaceTextSize.small.dynamicTypeSize < .medium)
        #expect(InterfaceTextSize.standard.dynamicTypeSize == .medium)
        #expect(InterfaceTextSize.large.dynamicTypeSize > .medium)
        #expect(
            InterfaceTextSize.standard.nativeSecondaryPointSize
                == 13
        )
        #expect(
            TrackTableDensity.compact.rowHeight
                < TrackTableDensity.standard.rowHeight
        )
        #expect(
            TrackTableDensity.standard.rowHeight
                < TrackTableDensity.comfortable.rowHeight
        )
        #expect(
            TrackListLayout.contentHeight(
                rowCount: 3,
                showsHeader: true,
                density: .comfortable
            ) == TrackTableDensity.comfortable.rowHeight * 3
                + TrackTableDensity.comfortable.headerHeight
        )
        let compact = NativeTrackRowHorizontalGeometry(
            rowHeight: TrackTableDensity.compact.rowHeight,
            leadingX: 72,
            showsArtwork: true,
            artworkSize: TrackTableDensity.compact.artworkSize
        )
        #expect(
            compact.artworkFrame?.width
                == TrackTableDensity.compact.artworkSize
        )
    }

    @Test("Track table reset restores only shared table presentation defaults")
    func trackTableReset() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        CadencePreferences.registerDefaults(in: defaults)
        defaults.set(false, forKey: CadencePreferences.Keys.showsTrackArtwork)
        defaults.set(
            TrackTableDensity.compact.rawValue,
            forKey: CadencePreferences.Keys.trackTableDensity
        )
        defaults.set("album", forKey: "trackTable.visibleColumns")
        defaults.set(2, forKey: "trackTable.columnDefaultsVersion")
        defaults.set(
            TrackTableSortField.year.rawValue,
            forKey: "trackTable.sortField"
        )
        defaults.set(
            TrackTableSortDirection.descending.rawValue,
            forKey: "trackTable.sortDirection"
        )
        defaults.set(
            InterfaceTextSize.large.rawValue,
            forKey: CadencePreferences.Keys.interfaceTextSize
        )

        TrackTablePreferences.reset(in: defaults)

        #expect(defaults.bool(forKey: CadencePreferences.Keys.showsTrackArtwork))
        #expect(CadencePreferences.trackTableDensity(in: defaults) == .standard)
        #expect(
            defaults.string(forKey: "trackTable.visibleColumns")
                == TrackTableColumn.defaultRawValue
        )
        #expect(defaults.integer(forKey: "trackTable.columnDefaultsVersion") == 2)
        #expect(
            defaults.string(forKey: "trackTable.sortField")
                == TrackTableSortField.song.rawValue
        )
        #expect(
            defaults.string(forKey: "trackTable.sortDirection")
                == TrackTableSortDirection.ascending.rawValue
        )
        #expect(CadencePreferences.interfaceTextSize(in: defaults) == .large)
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "AdvancedSettingsPreferencesTests-\(UUID().uuidString)"
        return try (#require(UserDefaults(suiteName: suite)), suite)
    }
}
