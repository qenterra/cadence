import AppKit
import QuartzCore
import SwiftUI

struct CadenceModeBackground: NSViewRepresentable {
    let palette: RhythmAccentPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func makeNSView(context _: Context) -> CadenceModeBackgroundView {
        CadenceModeBackgroundView()
    }

    func updateNSView(
        _ view: CadenceModeBackgroundView,
        context _: Context
    ) {
        view.update(
            palette: palette,
            appearance: .resolve(
                reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency,
                increasedContrast: colorSchemeContrast == .increased
            )
        )
    }
}

@MainActor
final class CadenceModeBackgroundView: NSView {
    private enum AnimationKey {
        static let primary = "cadence.background.primary"
        static let bloom = "cadence.background.bloom"
    }

    private let baseLayer = CALayer()
    private let primaryGradientLayer = CAGradientLayer()
    private let bloomGradientLayer = CAGradientLayer()
    private let scrimLayer = CAGradientLayer()

    private var palette: RhythmAccentPalette?
    private var backgroundAppearance: CadenceModeBackgroundAppearance?
    private var previousBounds = CGRect.null

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        true
    }

    override func layout() {
        super.layout()
        guard bounds != previousBounds else {
            return
        }
        previousBounds = bounds
        layoutLayers()
        installAnimationsIfNeeded()
    }

    func update(
        palette: RhythmAccentPalette,
        appearance: CadenceModeBackgroundAppearance
    ) {
        let paletteChanged = self.palette != palette
        let appearanceChanged = backgroundAppearance != appearance
        self.palette = palette
        backgroundAppearance = appearance

        if paletteChanged || appearanceChanged {
            updateLayerAppearance()
        }
        if appearanceChanged {
            installAnimationsIfNeeded()
        }
    }

    private func configureLayers() {
        wantsLayer = true
        guard let rootLayer = layer else {
            return
        }
        rootLayer.masksToBounds = true
        rootLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layerContentsRedrawPolicy = .never

        primaryGradientLayer.type = .conic
        primaryGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        primaryGradientLayer.endPoint = CGPoint(x: 0.5, y: 0)

        bloomGradientLayer.type = .radial
        bloomGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        bloomGradientLayer.endPoint = CGPoint(x: 1, y: 1)

        scrimLayer.type = .radial
        scrimLayer.startPoint = CGPoint(x: 0.5, y: 0.46)
        scrimLayer.endPoint = CGPoint(x: 1, y: 1)

        rootLayer.addSublayer(baseLayer)
        rootLayer.addSublayer(primaryGradientLayer)
        rootLayer.addSublayer(bloomGradientLayer)
        rootLayer.addSublayer(scrimLayer)
    }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        baseLayer.frame = bounds
        scrimLayer.frame = bounds

        let expandedBounds = bounds.insetBy(
            dx: -bounds.width * 0.28,
            dy: -bounds.height * 0.36
        )
        primaryGradientLayer.bounds = CGRect(
            origin: .zero,
            size: expandedBounds.size
        )
        primaryGradientLayer.position = CGPoint(
            x: bounds.midX,
            y: bounds.midY
        )

        bloomGradientLayer.bounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: bounds.width * 1.08,
                height: bounds.height * 1.18
            )
        )
        bloomGradientLayer.position = CGPoint(
            x: bounds.width * 0.34,
            y: bounds.height * 0.36
        )

        CATransaction.commit()
    }

    private func updateLayerAppearance() {
        guard let palette, let appearance = backgroundAppearance else {
            return
        }
        let colors = palette.backgroundColors.isEmpty
            ? RhythmAccentPalette.cadenceFallback.backgroundColors
            : palette.backgroundColors
        let expandedColors = softenedColorWheel(
            colors,
            opacity: appearance.fieldOpacity
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.backgroundColor = CGColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: appearance.baseOpacity
        )
        primaryGradientLayer.colors = expandedColors
        primaryGradientLayer.locations = evenlySpacedLocations(
            count: expandedColors.count
        )
        bloomGradientLayer.colors = bloomColors(
            colors,
            opacity: appearance.fieldOpacity
        )
        bloomGradientLayer.locations = [0, 0.34, 0.72, 1]
        scrimLayer.colors = [
            CGColor(red: 0, green: 0, blue: 0, alpha: 0.08),
            CGColor(
                red: 0,
                green: 0,
                blue: 0,
                alpha: appearance.scrimOpacity
            ),
        ]
        scrimLayer.locations = [0, 1]
        CATransaction.commit()
    }

    private func installAnimationsIfNeeded() {
        primaryGradientLayer.removeAnimation(forKey: AnimationKey.primary)
        bloomGradientLayer.removeAnimation(forKey: AnimationKey.bloom)

        guard
            let appearance = backgroundAppearance,
            appearance.isAnimated,
            !bounds.isEmpty
        else {
            return
        }

        let primaryRotation = CABasicAnimation(
            keyPath: "transform.rotation.z"
        )
        primaryRotation.fromValue = -0.22
        primaryRotation.toValue = Double.pi * 2 - 0.22

        let primaryScale = CAKeyframeAnimation(keyPath: "transform.scale")
        primaryScale.values = [1.02, 1.12, 1.05, 1.02]
        primaryScale.keyTimes = [0, 0.36, 0.72, 1]
        primaryScale.calculationMode = .cubic

        let primaryAnimation = CAAnimationGroup()
        primaryAnimation.animations = [primaryRotation, primaryScale]
        primaryAnimation.duration = appearance.animationDuration
        primaryAnimation.repeatCount = .infinity
        primaryAnimation.isRemovedOnCompletion = false
        primaryAnimation.preferredFrameRateRange = preferredFrameRateRange
        primaryGradientLayer.add(
            primaryAnimation,
            forKey: AnimationKey.primary
        )

        let bloomPosition = CAKeyframeAnimation(keyPath: "position")
        bloomPosition.values = [
            CGPoint(x: bounds.width * 0.28, y: bounds.height * 0.34),
            CGPoint(x: bounds.width * 0.72, y: bounds.height * 0.42),
            CGPoint(x: bounds.width * 0.58, y: bounds.height * 0.74),
            CGPoint(x: bounds.width * 0.24, y: bounds.height * 0.64),
            CGPoint(x: bounds.width * 0.28, y: bounds.height * 0.34),
        ]
        bloomPosition.keyTimes = [0, 0.24, 0.52, 0.78, 1]
        bloomPosition.calculationMode = .cubicPaced

        let bloomScale = CAKeyframeAnimation(keyPath: "transform.scale")
        bloomScale.values = [0.9, 1.16, 0.98, 0.9]
        bloomScale.keyTimes = [0, 0.38, 0.73, 1]
        bloomScale.calculationMode = .cubic

        let bloomAnimation = CAAnimationGroup()
        bloomAnimation.animations = [bloomPosition, bloomScale]
        bloomAnimation.duration = appearance.animationDuration * 0.82
        bloomAnimation.repeatCount = .infinity
        bloomAnimation.isRemovedOnCompletion = false
        bloomAnimation.preferredFrameRateRange = preferredFrameRateRange
        bloomGradientLayer.add(
            bloomAnimation,
            forKey: AnimationKey.bloom
        )
    }

    private var preferredFrameRateRange: CAFrameRateRange {
        let maximumFramesPerSecond = Float(
            window?.screen?.maximumFramesPerSecond ?? 60
        )
        return CAFrameRateRange(
            minimum: min(60, maximumFramesPerSecond),
            maximum: maximumFramesPerSecond,
            preferred: maximumFramesPerSecond
        )
    }

    private func softenedColorWheel(
        _ colors: [RhythmPulseColor],
        opacity: Double
    ) -> [CGColor] {
        guard let first = colors.first else {
            return []
        }
        var wheel: [RhythmPulseColor] = []
        for (index, color) in colors.enumerated() {
            let next = colors[(index + 1) % colors.count]
            wheel.append(color)
            wheel.append(color.mixed(with: next, amount: 0.5))
        }
        wheel.append(first)
        return wheel.map { $0.cgColor(alpha: opacity) }
    }

    private func bloomColors(
        _ colors: [RhythmPulseColor],
        opacity: Double
    ) -> [CGColor] {
        let first = colors.first
            ?? RhythmAccentPalette.cadenceFallback.colors[0]
        let second = colors.dropFirst().first ?? first
        return [
            first.cgColor(alpha: opacity * 0.78),
            second.cgColor(alpha: opacity * 0.46),
            first.cgColor(alpha: opacity * 0.14),
            first.cgColor(alpha: 0),
        ]
    }

    private func evenlySpacedLocations(count: Int) -> [NSNumber] {
        guard count > 1 else {
            return [0]
        }
        return (0 ..< count).map {
            NSNumber(value: Double($0) / Double(count - 1))
        }
    }
}

private extension RhythmPulseColor {
    func mixed(
        with other: RhythmPulseColor,
        amount: Double
    ) -> RhythmPulseColor {
        let clampedAmount = min(max(amount, 0), 1)
        return RhythmPulseColor(
            red: red + (other.red - red) * clampedAmount,
            green: green + (other.green - green) * clampedAmount,
            blue: blue + (other.blue - blue) * clampedAmount
        )
    }

    func cgColor(alpha: Double) -> CGColor {
        CGColor(
            red: red,
            green: green,
            blue: blue,
            alpha: min(max(alpha, 0), 1)
        )
    }
}
