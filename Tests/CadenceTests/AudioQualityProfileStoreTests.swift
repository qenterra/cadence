@testable import Cadence
import Foundation
import Testing

@MainActor
struct AudioQualityProfileStoreTests {
    @Test("Quality profile survives a new store instance")
    func persistence() throws {
        let suiteName = "CadenceTests.\(UUID().uuidString)"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let first = UserDefaultsAudioQualityProfileStore(
            defaults: defaults
        )
        first.save(.pure)
        let second = UserDefaultsAudioQualityProfileStore(
            defaults: defaults
        )

        #expect(second.load() == .pure)
    }

    @Test("Stereo spatialization preference survives a new store instance")
    func spatializationPersistence() throws {
        let suiteName = "CadenceTests.\(UUID().uuidString)"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        UserDefaultsAudioQualityProfileStore(defaults: defaults)
            .saveStereoSpatializationEnabled(true)

        #expect(
            UserDefaultsAudioQualityProfileStore(defaults: defaults)
                .loadStereoSpatializationEnabled()
        )
    }
}
