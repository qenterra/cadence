import SwiftUI

struct RhythmPulseCanvas: NSViewRepresentable {
    let store: RhythmPulseStore
    let panelStartX: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context _: Context) -> RhythmPulseCompositorView {
        RhythmPulseCompositorView()
    }

    func updateNSView(
        _ view: RhythmPulseCompositorView,
        context _: Context
    ) {
        store.attachCompositor(view)
        view.update(
            RhythmPulseCompositorState(
                washes: store.renderWashes,
                particles: store.renderParticles,
                visualQATime: store.visualQATime,
                panelStartX: panelStartX,
                appearance: store.palette.map {
                    RhythmPulseAppearance.resolve(
                        mode: colorScheme == .dark ? .dark : .light,
                        palette: $0
                    )
                },
                reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency
            )
        )
    }
}
