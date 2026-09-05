@testable import Cadence
import simd
import Testing

struct CadenceModePaletteTransitionTests {
    @Test("Track palettes morph through linear shader colors")
    func trackPalettesMorphThroughLinearColors() {
        let black = RhythmAccentPalette(colors: [
            RhythmPulseColor(red: 0, green: 0, blue: 0),
        ])
        let white = RhythmAccentPalette(colors: [
            RhythmPulseColor(red: 1, green: 1, blue: 1),
        ])
        var transition = CadenceModeGradientPaletteTransition(
            palette: black
        )

        transition.retarget(
            to: white,
            at: 10,
            reduceMotion: false
        )

        let target = CadenceModeGradientReference.shaderColors(for: white)
        let start = transition.colors(at: 10)
        let midpoint = transition.colors(
            at: 10 + CadenceModeGradientPaletteTransition.duration / 2
        )
        let end = transition.colors(
            at: 10 + CadenceModeGradientPaletteTransition.duration
        )

        #expect(start.allSatisfy { $0 == .zero })
        #expect(zip(midpoint, target).allSatisfy { color, targetColor in
            paletteColorsApproximatelyEqual(color, targetColor * 0.5)
        })
        #expect(zip(end, target).allSatisfy { color, targetColor in
            paletteColorsApproximatelyEqual(color, targetColor)
        })
    }

    @Test("A rapid track change continues from the visible palette")
    func rapidTrackChangeIsInterruptible() {
        let black = RhythmAccentPalette(colors: [
            RhythmPulseColor(red: 0, green: 0, blue: 0),
        ])
        let white = RhythmAccentPalette(colors: [
            RhythmPulseColor(red: 1, green: 1, blue: 1),
        ])
        let red = RhythmAccentPalette(colors: [
            RhythmPulseColor(red: 1, green: 0, blue: 0),
        ])
        var transition = CadenceModeGradientPaletteTransition(
            palette: black
        )
        transition.retarget(to: white, at: 2, reduceMotion: false)
        let interruptionTime = 2
            + CadenceModeGradientPaletteTransition.duration / 2
        let visibleColors = transition.colors(at: interruptionTime)

        transition.retarget(
            to: red,
            at: interruptionTime,
            reduceMotion: false
        )

        #expect(
            zip(transition.colors(at: interruptionTime), visibleColors)
                .allSatisfy { color, visibleColor in
                    paletteColorsApproximatelyEqual(color, visibleColor)
                }
        )
    }

    @Test("Reduce Motion replaces the palette immediately")
    func reduceMotionReplacesPaletteImmediately() {
        let black = RhythmAccentPalette(colors: [
            RhythmPulseColor(red: 0, green: 0, blue: 0),
        ])
        let blue = RhythmAccentPalette(colors: [
            RhythmPulseColor(red: 0, green: 0, blue: 1),
        ])
        var transition = CadenceModeGradientPaletteTransition(
            palette: black
        )

        transition.retarget(to: blue, at: 4, reduceMotion: true)

        #expect(
            zip(
                transition.colors(at: 4),
                CadenceModeGradientReference.shaderColors(for: blue)
            ).allSatisfy { color, targetColor in
                paletteColorsApproximatelyEqual(color, targetColor)
            }
        )
    }
}

private func paletteColorsApproximatelyEqual(
    _ lhs: SIMD3<Float>,
    _ rhs: SIMD3<Float>,
    tolerance: Float = 0.000_01
) -> Bool {
    simd_distance(lhs, rhs) <= tolerance
}
