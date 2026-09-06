import QenTerraMediaComponents
import SwiftUI

struct CadenceModeBackground: View {
    let palette: RhythmAccentPalette
    var hasLiveEffects = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cadenceModeVisualQABackgroundReduceMotionOverride)
    private var visualQAReduceMotionOverride

    var body: some View {
        ArtworkAccentGradient(
            palette: CadenceAccentGradientAdapter.palette(from: palette),
            appearance: CadenceAccentGradientAdapter.appearance(
                palette: palette, hasLiveEffects: hasLiveEffects,
                reduceMotion: visualQAReduceMotionOverride ?? reduceMotion
            )
        )
    }
}
