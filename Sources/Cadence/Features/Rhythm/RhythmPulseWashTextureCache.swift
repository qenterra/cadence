import CoreGraphics

@MainActor
final class RhythmPulseWashTextureCache {
    private struct Key: Hashable {
        let color: RhythmPulseColor
        let reduceTransparency: Bool
    }

    private var images: [Key: CGImage] = [:]

    func prepare(
        colors: [RhythmPulseColor],
        reduceTransparency: Bool
    ) {
        for color in colors {
            _ = image(
                color: color,
                reduceTransparency: reduceTransparency
            )
        }
    }

    func image(
        color: RhythmPulseColor,
        reduceTransparency: Bool
    ) -> CGImage? {
        let key = Key(
            color: color,
            reduceTransparency: reduceTransparency
        )
        if let image = images[key] {
            return image
        }
        guard let image = makeImage(for: key) else {
            return nil
        }
        images[key] = image
        return image
    }

    private func makeImage(for key: Key) -> CGImage? {
        let dimension = 160
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: dimension,
                height: dimension,
                bitsPerComponent: 8,
                bytesPerRow: dimension * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        let opacity = key.reduceTransparency ? 0.46 : 0.8
        let colors = [
            makeCGColor(key.color, alpha: opacity),
            makeCGColor(key.color, alpha: opacity * 0.34),
            makeCGColor(key.color, alpha: 0),
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors,
            locations: [0, 0.58, 1]
        ) else {
            return nil
        }

        let center = CGPoint(
            x: CGFloat(dimension) * 0.5,
            y: CGFloat(dimension) * 0.5
        )
        context.interpolationQuality = .high
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: CGFloat(dimension) * 0.5,
            options: [.drawsAfterEndLocation]
        )
        return context.makeImage()
    }

    private func makeCGColor(
        _ color: RhythmPulseColor,
        alpha: Double
    ) -> CGColor {
        CGColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: min(max(alpha, 0), 1)
        )
    }
}
