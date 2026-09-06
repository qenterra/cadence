@testable import Cadence
import QenTerraDesignTokens
import QenTerraMediaComponents
import simd

/// Keep the existing consumer fixtures and numeric assertions while exercising shared APIs.
extension ArtworkAccentGradientReference {
    static func shaderColors(for palette: RhythmAccentPalette) -> [SIMD3<Float>] {
        shaderColors(for: CadenceAccentGradientAdapter.palette(from: palette))
    }
}

extension ArtworkAccentGradientTransition {
    init(palette: RhythmAccentPalette) {
        self.init(palette: CadenceAccentGradientAdapter.palette(from: palette))
    }

    mutating func retarget(to palette: RhythmAccentPalette, at timestamp: Double, reduceMotion: Bool) {
        retarget(to: CadenceAccentGradientAdapter.palette(from: palette), at: timestamp, reducesMotion: reduceMotion)
    }
}

extension ArtworkAccentGradientAppearance {
    static func resolve(reduceMotion: Bool, reduceTransparency: Bool, increasedContrast: Bool) -> Self {
        .resolve(palette: .fallback, isEffectActive: false, environment: DesignNativeEnvironment(
            appearance: .light, productProfile: .cadence, density: .standard, isIncreasedContrast: increasedContrast,
            reducesMotion: reduceMotion, reducesTransparency: reduceTransparency
        ))
    }
}

extension ArtworkAccentGradientView {
    func update(palette: RhythmAccentPalette, appearance: ArtworkAccentGradientAppearance) {
        update(palette: CadenceAccentGradientAdapter.palette(from: palette), appearance: appearance)
    }
}

enum AdoptedGradientContrast {
    static func opacity(for palette: RhythmAccentPalette) -> Double {
        ArtworkAccentGradientTint.baseOpacity(for: CadenceAccentGradientAdapter.palette(from: palette))
    }

    static func activeTintOpacity(for palette: RhythmAccentPalette) -> Double {
        CadenceAccentGradientAdapter.appearance(palette: palette, hasLiveEffects: true, reduceMotion: false).tint.amount
    }

    static func tint(for palette: RhythmAccentPalette) -> ArtworkAccentColor {
        CadenceAccentGradientAdapter.appearance(palette: palette, hasLiveEffects: true, reduceMotion: false).tint.color
    }

    static func transitionDuration(hasLiveEffects: Bool, reduceMotion: Bool) -> Double {
        CadenceAccentGradientAdapter.appearance(
            palette: .cadenceFallback, hasLiveEffects: hasLiveEffects, reduceMotion: reduceMotion
        ).tint.transitionDuration
    }
}
