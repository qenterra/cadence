import QenTerraMediaComponents

enum CadenceAccentGradientAdapter {
    static func palette(from palette: RhythmAccentPalette) -> ArtworkAccentPalette {
        guard !palette.colors.isEmpty else { return .fallback }
        return ArtworkAccentPalette(colors: palette.colors.map {
            ArtworkAccentColor(red: $0.red, green: $0.green, blue: $0.blue)
        })
    }

    static func appearance(
        palette: RhythmAccentPalette,
        hasLiveEffects: Bool,
        reduceMotion: Bool,
        maximumFramesPerSecond: Int = 60
    ) -> ArtworkAccentGradientAppearance {
        ArtworkAccentGradientAppearance(
            isAnimated: !reduceMotion,
            maximumFramesPerSecond: maximumFramesPerSecond,
            tint: .resolve(
                palette: self.palette(from: palette),
                isEffectActive: hasLiveEffects,
                reducesMotion: reduceMotion
            )
        )
    }
}
