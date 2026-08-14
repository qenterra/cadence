import QuartzCore

struct CadenceModeBackgroundAnimations {
    let primary: CAAnimationGroup
    let bloom: CAAnimationGroup

    static func make(
        in bounds: CGRect,
        appearance: CadenceModeBackgroundAppearance,
        frameRateRange: CAFrameRateRange
    ) -> CadenceModeBackgroundAnimations {
        CadenceModeBackgroundAnimations(
            primary: primaryAnimation(
                in: bounds,
                appearance: appearance,
                frameRateRange: frameRateRange
            ),
            bloom: bloomAnimation(
                in: bounds,
                appearance: appearance,
                frameRateRange: frameRateRange
            )
        )
    }

    private static func primaryAnimation(
        in bounds: CGRect,
        appearance: CadenceModeBackgroundAppearance,
        frameRateRange: CAFrameRateRange
    ) -> CAAnimationGroup {
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.02, 1.12, 1.05, 1.02]
        scale.keyTimes = [0, 0.36, 0.72, 1]
        scale.calculationMode = .cubic

        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = [
            CGPoint(x: bounds.width * 0.46, y: bounds.height * 0.48),
            CGPoint(x: bounds.width * 0.56, y: bounds.height * 0.43),
            CGPoint(x: bounds.width * 0.54, y: bounds.height * 0.56),
            CGPoint(x: bounds.width * 0.44, y: bounds.height * 0.55),
            CGPoint(x: bounds.width * 0.46, y: bounds.height * 0.48),
        ]
        position.keyTimes = [0, 0.24, 0.52, 0.78, 1]
        position.calculationMode = .cubicPaced
        return group(
            animations: [scale, position],
            duration: appearance.animationDuration,
            frameRateRange: frameRateRange
        )
    }

    private static func bloomAnimation(
        in bounds: CGRect,
        appearance: CadenceModeBackgroundAppearance,
        frameRateRange: CAFrameRateRange
    ) -> CAAnimationGroup {
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = [
            CGPoint(x: bounds.width * 0.28, y: bounds.height * 0.34),
            CGPoint(x: bounds.width * 0.72, y: bounds.height * 0.42),
            CGPoint(x: bounds.width * 0.58, y: bounds.height * 0.74),
            CGPoint(x: bounds.width * 0.24, y: bounds.height * 0.64),
            CGPoint(x: bounds.width * 0.28, y: bounds.height * 0.34),
        ]
        position.keyTimes = [0, 0.24, 0.52, 0.78, 1]
        position.calculationMode = .cubicPaced

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.9, 1.16, 0.98, 0.9]
        scale.keyTimes = [0, 0.38, 0.73, 1]
        scale.calculationMode = .cubic
        return group(
            animations: [position, scale],
            duration: appearance.animationDuration * 0.82,
            frameRateRange: frameRateRange
        )
    }

    private static func group(
        animations: [CAAnimation],
        duration: TimeInterval,
        frameRateRange: CAFrameRateRange
    ) -> CAAnimationGroup {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        group.preferredFrameRateRange = frameRateRange
        return group
    }
}
