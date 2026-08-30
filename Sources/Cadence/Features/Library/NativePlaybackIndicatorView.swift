import AppKit
import QuartzCore

@MainActor
final class NativePlaybackIndicatorView: NSView {
    private static let animationKey = "cadence.playback.level"
    private static let staticScales: [CGFloat] = [0.48, 0.82, 0.62]
    private let bars = (0 ..< 3).map { _ in CALayer() }

    private(set) var isAnimating = false

    var barCount: Int {
        bars.count
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.actions = Self.disabledLayerActions
        for bar in bars {
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.backgroundColor = NSColor.white.cgColor
            bar.cornerRadius = 1.5
            bar.actions = Self.disabledLayerActions
            layer?.addSublayer(bar)
        }
        applyStaticBars()
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let barWidth: CGFloat = 3
        let gap: CGFloat = 2.5
        let height: CGFloat = min(17, max(bounds.height - 14, 1))
        let totalWidth = CGFloat(bars.count) * barWidth
            + CGFloat(max(bars.count - 1, 0)) * gap
        let originX = (bounds.width - totalWidth) / 2
        let originY = (bounds.height - height) / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(
                x: 0,
                y: 0,
                width: barWidth,
                height: height
            )
            bar.position = CGPoint(
                x: originX + barWidth / 2
                    + CGFloat(index) * (barWidth + gap),
                y: originY
            )
        }
        CATransaction.commit()
    }

    func setPlaying(_ isPlaying: Bool, reduceMotion: Bool) {
        let shouldAnimate = isPlaying && !reduceMotion
        guard shouldAnimate != isAnimating else {
            if !shouldAnimate {
                applyStaticBars()
            }
            return
        }
        isAnimating = shouldAnimate
        if shouldAnimate {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    private func startAnimating() {
        let durations: [CFTimeInterval] = [1.20, 1.38, 1.28]
        let patterns: [[CGFloat]] = [
            [0.32, 0.94, 0.54, 0.76, 0.32],
            [0.72, 0.38, 1, 0.58, 0.72],
            [0.46, 0.82, 0.34, 0.96, 0.46],
        ]
        let now = CACurrentMediaTime()
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: Self.animationKey)
            let animation = CAKeyframeAnimation(
                keyPath: "transform.scale.y"
            )
            animation.values = patterns[index]
            animation.keyTimes = [0, 0.24, 0.5, 0.76, 1]
            animation.duration = durations[index]
            animation.beginTime = now + Double(index) * 0.10
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = true
            bar.add(animation, forKey: Self.animationKey)
        }
    }

    private func stopAnimating() {
        for bar in bars {
            bar.removeAnimation(forKey: Self.animationKey)
        }
        applyStaticBars()
    }

    private func applyStaticBars() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.transform = CATransform3DMakeScale(
                1,
                Self.staticScales[index],
                1
            )
        }
        CATransaction.commit()
    }

    private static let disabledLayerActions: [String: any CAAction] = [
        "bounds": NSNull(),
        "position": NSNull(),
        "transform": NSNull(),
    ]
}
