import CoreGraphics

struct RhythmFocusLayout: Sendable {
    private static let outerMargin: CGFloat = 24
    private static let standardInset: CGFloat = 42
    private static let lyricsGap: CGFloat = 20

    let canvasSize: CGSize
    let contextWidth: CGFloat

    var standardArtworkFrame: CGRect {
        let availableWidth = max(
            contextWidth - Self.standardInset * 2,
            0
        )
        let availableHeight = max(
            canvasSize.height - Self.standardInset * 2,
            0
        )
        let size = min(availableWidth, availableHeight, 420)
        return CGRect(
            x: Self.standardInset,
            y: Self.standardInset,
            width: size,
            height: size
        )
    }

    var focusArtworkFrame: CGRect {
        let size = min(
            420,
            canvasSize.width * 0.4,
            canvasSize.height * 0.46
        )
        let centerY = max(
            Self.outerMargin + size * 0.5,
            canvasSize.height * 0.38
        )
        return CGRect(
            x: (canvasSize.width - size) * 0.5,
            y: centerY - size * 0.5,
            width: size,
            height: size
        )
    }

    var focusLyricSlotHeight: CGFloat {
        let availableHeight = max(
            canvasSize.height - Self.outerMargin
                - focusArtworkFrame.maxY - Self.lyricsGap,
            0
        )
        return min(max(availableHeight / 5, 32), 52)
    }

    var focusLyricsFrame: CGRect {
        let width = min(canvasSize.width - Self.outerMargin * 2, 760)
        return CGRect(
            x: (canvasSize.width - width) * 0.5,
            y: focusArtworkFrame.maxY + Self.lyricsGap,
            width: width,
            height: focusLyricSlotHeight * 5
        )
    }

    func emitterOrigin(
        lane: RhythmLane,
        isFocused: Bool
    ) -> CGPoint {
        let frame = isFocused
            ? focusArtworkFrame
            : standardArtworkFrame
        let horizontalPosition: CGFloat = lane == .left ? 0.06 : 0.94
        return CGPoint(
            x: frame.minX + frame.width * horizontalPosition,
            y: frame.midY
        )
    }

    func normalizedEmitterOrigin(
        lane: RhythmLane,
        isFocused: Bool
    ) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return .zero
        }
        let origin = emitterOrigin(lane: lane, isFocused: isFocused)
        return CGPoint(
            x: origin.x / canvasSize.width,
            y: origin.y / canvasSize.height
        )
    }
}
