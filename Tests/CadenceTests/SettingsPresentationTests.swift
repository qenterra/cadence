@testable import Cadence
import Foundation
import Testing

struct SettingsPresentationTests {
    @Test("Cadence Mode options have stable product defaults")
    func cadenceModeOptionDefaults() {
        #expect(CadenceModeOptions.default == CadenceModeOptions(
            isEnabled: true,
            reactsToBass: true,
            showsLyrics: true,
            showsTrackInformation: true,
            staysActive: false
        ))
    }

    @Test("Cadence Mode options persist through stable preference keys")
    func cadenceModeOptionPersistence() throws {
        let suiteName = "CadenceModeOptionsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(CadenceModeOptions.load(from: defaults) == .default)

        defaults.set(false, forKey: CadenceModePreferences.isEnabledKey)
        defaults.set(false, forKey: CadenceModePreferences.reactsToBassKey)
        defaults.set(false, forKey: CadenceModePreferences.showsLyricsKey)
        defaults.set(
            false,
            forKey: CadenceModePreferences.showsTrackInformationKey
        )
        defaults.set(true, forKey: CadenceModePreferences.staysActiveKey)

        #expect(CadenceModeOptions.load(from: defaults) == CadenceModeOptions(
            isEnabled: false,
            reactsToBass: false,
            showsLyrics: false,
            showsTrackInformation: false,
            staysActive: true
        ))
    }

    @Test("Shortcut reference documents Cadence Mode with literal Z and X")
    func cadenceModeShortcutReference() throws {
        let entry = try #require(
            ShortcutCatalog.entries.first { $0.id == "cadence-mode" }
        )

        #expect(entry.title == "Cadence Mode")
        #expect(entry.keys == [.z, .x])
        #expect(entry.keys.map(\.glyph) == ["Z", "X"])
    }
}
