import Foundation

@MainActor
protocol AudioQualityProfileStoring: AnyObject {
    func load() -> AudioQualityProfile
    func save(_ profile: AudioQualityProfile)
    func loadStereoSpatializationEnabled() -> Bool
    func saveStereoSpatializationEnabled(_ enabled: Bool)
}

@MainActor
final class VolatileAudioQualityProfileStore: AudioQualityProfileStoring {
    private var profile: AudioQualityProfile
    private var stereoSpatializationEnabled: Bool

    init(
        profile: AudioQualityProfile = .adaptive,
        stereoSpatializationEnabled: Bool = false
    ) {
        self.profile = profile
        self.stereoSpatializationEnabled = stereoSpatializationEnabled
    }

    func load() -> AudioQualityProfile {
        profile
    }

    func save(_ profile: AudioQualityProfile) {
        self.profile = profile
    }

    func loadStereoSpatializationEnabled() -> Bool {
        stereoSpatializationEnabled
    }

    func saveStereoSpatializationEnabled(_ enabled: Bool) {
        stereoSpatializationEnabled = enabled
    }
}

@MainActor
final class UserDefaultsAudioQualityProfileStore:
    AudioQualityProfileStoring {
    private let defaults: UserDefaults
    private let key = "audioQualityProfile"
    private let stereoSpatializationKey = "stereoSpatializationEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AudioQualityProfile {
        defaults.string(forKey: key)
            .flatMap(AudioQualityProfile.init(rawValue:))
            ?? .adaptive
    }

    func save(_ profile: AudioQualityProfile) {
        defaults.set(profile.rawValue, forKey: key)
    }

    func loadStereoSpatializationEnabled() -> Bool {
        defaults.bool(forKey: stereoSpatializationKey)
    }

    func saveStereoSpatializationEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: stereoSpatializationKey)
    }
}
