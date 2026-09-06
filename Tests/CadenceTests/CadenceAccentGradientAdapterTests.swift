@testable import Cadence
import QenTerraMediaComponents
import Testing

struct CadenceAccentGradientAdapterTests {
    @Test func rhythmPaletteMapsDisplayColoursWithoutDoubleLinearization() {
        let source = RhythmAccentPalette(colors: [
            RhythmPulseColor(red: 0.25, green: 0.5, blue: 0.75),
            RhythmPulseColor(red: 1, green: 0.25, blue: 0.125),
            RhythmPulseColor(red: 0.2, green: 0.3, blue: 0.4),
            RhythmPulseColor(red: 0.4, green: 0.3, blue: 0.2),
            RhythmPulseColor(red: 0.9, green: 0.8, blue: 0.7),
        ])
        let mapped = CadenceAccentGradientAdapter.palette(from: source)
        #expect(mapped.colors.count == 5)
        #expect(mapped.colors[0] == ArtworkAccentColor(red: 0.25, green: 0.5, blue: 0.75))
        #expect(CadenceAccentGradientAdapter.palette(from: RhythmAccentPalette(colors: [])) == .fallback)
        for active in [false, true] {
            let appearance = CadenceAccentGradientAdapter.appearance(
                palette: source, hasLiveEffects: active, reduceMotion: false
            )
            #expect(appearance.isAnimated)
            #expect(appearance.maximumFramesPerSecond == 60)
            #expect(appearance.tint.transitionDuration == 1.4)
            #expect((appearance.tint.amount > 0) == active)
        }
        #expect(!CadenceAccentGradientAdapter.appearance(
            palette: source, hasLiveEffects: true, reduceMotion: true
        ).isAnimated)
        #expect(ArtworkAccentGradientTransition.duration == 0.8)
    }
}
