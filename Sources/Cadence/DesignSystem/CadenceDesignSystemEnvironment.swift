import QenTerraComponents
import QenTerraDesignTokens
import QenTerraMediaComponents

enum CadenceDesignSystemEnvironment {
    static func configuration(
        for appearance: CadenceAppearance
    ) -> DesignSystemConfiguration {
        DesignSystemConfiguration(
            appearance: DesignAppearancePreference(
                rawValue: appearance.rawValue
            ) ?? .system,
            productProfile: .cadence,
            density: .standard
        )
    }

    static func settingsConfiguration(
        for appearance: CadenceAppearance
    ) -> DesignSystemConfiguration {
        configuration(for: appearance)
    }
}
