import SwiftUI

struct CadenceModeBackground: View {
    let palette: RhythmAccentPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        GeometryReader { geometry in
            TimelineView(
                .animation(
                    minimumInterval: 1 / 30,
                    paused: !appearance.isAnimated
                )
            ) { timeline in
                ZStack {
                    Color.black.opacity(appearance.baseOpacity)

                    let indexedColors = Array(colors.enumerated())
                    ForEach(indexedColors, id: \.offset) { indexedColor in
                        field(
                            color: indexedColor.element,
                            index: indexedColor.offset,
                            time: timeline.date.timeIntervalSinceReferenceDate,
                            canvasSize: geometry.size
                        )
                    }

                    Color.black.opacity(appearance.scrimOpacity)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var appearance: CadenceModeBackgroundAppearance {
        .resolve(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            increasedContrast: colorSchemeContrast == .increased
        )
    }

    private var colors: [RhythmPulseColor] {
        let artworkColors = palette.backgroundColors
        return artworkColors.isEmpty
            ? RhythmAccentPalette.cadenceFallback.backgroundColors
            : artworkColors
    }

    private func field(
        color: RhythmPulseColor,
        index: Int,
        time: TimeInterval,
        canvasSize: CGSize
    ) -> some View {
        let phase = appearance.isAnimated
            ? time / 14 + Double(index) * 1.71
            : Double(index) * 1.71
        let horizontalCenter = canvasSize.width
            * (0.5 + 0.24 * sin(phase))
        let verticalCenter = canvasSize.height
            * (0.5 + 0.2 * cos(phase * 0.83))
        let scale = 0.92 + 0.12 * sin(phase * 0.71)

        return Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(
                            red: color.red,
                            green: color.green,
                            blue: color.blue
                        )
                        .opacity(appearance.fieldOpacity),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(canvasSize.width, canvasSize.height) * 0.46
                )
            )
            .frame(
                width: canvasSize.width * 0.94,
                height: canvasSize.height * 0.88
            )
            .scaleEffect(scale)
            .blur(radius: appearance.blurRadius)
            .position(x: horizontalCenter, y: verticalCenter)
    }
}
