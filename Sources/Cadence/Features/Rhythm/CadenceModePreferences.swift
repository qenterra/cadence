import Foundation

enum CadenceModePreferences {
    static let isEnabledKey = "cadenceMode.isEnabled"
    static let reactsToBassKey = "cadenceMode.reactsToBass"
    static let showsLyricsKey = "cadenceMode.showsLyrics"
    static let showsTrackInformationKey =
        "cadenceMode.showsTrackInformation"
    static let staysActiveKey = "cadenceMode.staysActive"
}

struct CadenceModeOptions: Hashable, Sendable {
    let isEnabled: Bool
    let reactsToBass: Bool
    let showsLyrics: Bool
    let showsTrackInformation: Bool
    let staysActive: Bool

    static let `default` = Self(
        isEnabled: true,
        reactsToBass: true,
        showsLyrics: true,
        showsTrackInformation: true,
        staysActive: false
    )

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(
            isEnabled: value(
                forKey: CadenceModePreferences.isEnabledKey,
                fallback: Self.default.isEnabled,
                defaults: defaults
            ),
            reactsToBass: value(
                forKey: CadenceModePreferences.reactsToBassKey,
                fallback: Self.default.reactsToBass,
                defaults: defaults
            ),
            showsLyrics: value(
                forKey: CadenceModePreferences.showsLyricsKey,
                fallback: Self.default.showsLyrics,
                defaults: defaults
            ),
            showsTrackInformation: value(
                forKey: CadenceModePreferences.showsTrackInformationKey,
                fallback: Self.default.showsTrackInformation,
                defaults: defaults
            ),
            staysActive: value(
                forKey: CadenceModePreferences.staysActiveKey,
                fallback: Self.default.staysActive,
                defaults: defaults
            )
        )
    }

    private static func value(
        forKey key: String,
        fallback: Bool,
        defaults: UserDefaults
    ) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}

enum CadenceModeTimeoutPolicy: Equatable, Sendable {
    case inactivity(TimeInterval)
    case persistent

    func deadline(after time: TimeInterval) -> TimeInterval? {
        switch self {
        case let .inactivity(duration):
            time + duration
        case .persistent:
            nil
        }
    }
}
