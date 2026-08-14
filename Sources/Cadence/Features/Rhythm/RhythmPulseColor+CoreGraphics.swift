import CoreGraphics

extension RhythmPulseColor {
    func cgColor(alpha: Double) -> CGColor {
        CGColor(
            red: red,
            green: green,
            blue: blue,
            alpha: min(max(alpha, 0), 1)
        )
    }
}
