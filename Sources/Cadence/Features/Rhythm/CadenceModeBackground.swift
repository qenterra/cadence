import AppKit
import MetalKit
import QenTerraMediaComponents
import SwiftUI

struct CadenceModeBackground: View {
    let palette: RhythmAccentPalette
    let maximumFramesPerSecond: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cadenceModeVisualQABackgroundReduceMotionOverride)
    private var visualQAReduceMotionOverride

    init(
        palette: RhythmAccentPalette,
        maximumFramesPerSecond: Int = 60
    ) {
        self.palette = palette
        self.maximumFramesPerSecond = maximumFramesPerSecond
    }

    var body: some View {
        GeometryReader { geometry in
            if visualQAReduceMotionOverride == true,
               let snapshot = makeSnapshot(size: geometry.size) {
                Image(
                    decorative: snapshot.image,
                    scale: snapshot.scale
                )
                .resizable()
                .interpolation(.high)
            } else {
                TerrainSurface(
                    palette: palette,
                    reduceMotion: reduceMotion,
                    maximumFramesPerSecond: maximumFramesPerSecond
                )
            }
        }
    }

    private func makeSnapshot(size: CGSize) -> (image: CGImage, scale: CGFloat)? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let view = ArtworkAccentGradientView(
            frame: CGRect(origin: .zero, size: size),
            device: MTLCreateSystemDefaultDevice()
        )
        view.appliesAppearanceOverlays = false
        view.update(
            palette: CadenceAccentGradientAdapter.palette(from: palette),
            appearance: CadenceAccentGradientAdapter.appearance(
                palette: palette,
                hasLiveEffects: false,
                reduceMotion: true,
                maximumFramesPerSecond: maximumFramesPerSecond
            )
        )
        let pixelSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
        return view.makeSnapshot(size: pixelSize, time: 0).map {
            ($0, scale)
        }
    }

    private struct TerrainSurface: NSViewRepresentable {
        let palette: RhythmAccentPalette
        let reduceMotion: Bool
        let maximumFramesPerSecond: Int

        func makeNSView(context _: Context) -> ArtworkAccentGradientView {
            let view = ArtworkAccentGradientView(
                frame: .zero,
                device: MTLCreateSystemDefaultDevice()
            )
            view.appliesAppearanceOverlays = false
            return view
        }

        func updateNSView(
            _ view: ArtworkAccentGradientView,
            context _: Context
        ) {
            view.update(
                palette: CadenceAccentGradientAdapter.palette(from: palette),
                appearance: CadenceAccentGradientAdapter.appearance(
                    palette: palette,
                    hasLiveEffects: false,
                    reduceMotion: reduceMotion,
                    maximumFramesPerSecond: maximumFramesPerSecond
                )
            )
        }
    }
}
