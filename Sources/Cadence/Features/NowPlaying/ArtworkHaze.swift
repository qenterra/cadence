import SwiftUI

struct ArtworkHaze: View {
    let palette: ArtworkPalette

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            CadenceTheme.contentBackground
        } else {
            ZStack {
                CadenceTheme.contentBackground

                RadialGradient(
                    colors: [
                        hazeColor.opacity(0.16),
                        hazeColor.opacity(0.035),
                        .clear,
                    ],
                    center: .topLeading,
                    startRadius: 24,
                    endRadius: 620
                )

                RadialGradient(
                    colors: [
                        secondaryHazeColor.opacity(0.07),
                        .clear,
                    ],
                    center: .bottomTrailing,
                    startRadius: 30,
                    endRadius: 520
                )
            }
        }
    }

    private var hazeColor: Color {
        switch palette {
        case .amberNoir: Color(red: 0.58, green: 0.30, blue: 0.10)
        case .arctic: Color(red: 0.40, green: 0.68, blue: 0.78)
        case .blueHour: Color(red: 0.10, green: 0.31, blue: 0.66)
        case .ember: Color(red: 0.68, green: 0.15, blue: 0.08)
        case .forest: Color(red: 0.16, green: 0.42, blue: 0.28)
        case .lilac: Color(red: 0.45, green: 0.30, blue: 0.58)
        case .ocean: Color(red: 0.04, green: 0.39, blue: 0.50)
        case .rose: Color(red: 0.58, green: 0.18, blue: 0.30)
        case .silver: Color(red: 0.38, green: 0.41, blue: 0.45)
        case .sunset: Color(red: 0.72, green: 0.25, blue: 0.12)
        }
    }

    private var secondaryHazeColor: Color {
        hazeColor.opacity(0.6)
    }
}
