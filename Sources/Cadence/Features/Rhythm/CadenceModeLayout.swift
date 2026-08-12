import CoreGraphics

struct CadenceModeLayout: Hashable, Sendable {
    private static let outerMargin: CGFloat = 24
    private static let standardInset: CGFloat = 42
    private static let lyricsGap: CGFloat = 20
    private static let minimumLyricSlotHeight: CGFloat = 32
    private static let maximumLyricSlotHeight: CGFloat = 52
    private static let maximumModeArtworkSize: CGFloat = 960

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

    var modeArtworkFrame: CGRect {
        let availableHeight = max(
            canvasSize.height - Self.outerMargin * 2,
            0
        )
        let minimumLyricsHeight = Self.minimumLyricSlotHeight * 5
        let size = max(
            min(
                Self.maximumModeArtworkSize,
                canvasSize.width * 0.36,
                availableHeight - Self.lyricsGap - minimumLyricsHeight
            ),
            0
        )
        let compositionHeight = size
            + Self.lyricsGap
            + modeLyricSlotHeight(forArtworkSize: size) * 5
        let originY = Self.outerMargin + max(
            (availableHeight - compositionHeight) * 0.5,
            0
        )
        return CGRect(
            x: (canvasSize.width - size) * 0.5,
            y: originY,
            width: size,
            height: size
        )
    }

    var modeLyricSlotHeight: CGFloat {
        modeLyricSlotHeight(forArtworkSize: modeArtworkFrame.height)
    }

    private func modeLyricSlotHeight(
        forArtworkSize artworkSize: CGFloat
    ) -> CGFloat {
        let availableHeight = max(
            canvasSize.height - Self.outerMargin * 2
                - artworkSize - Self.lyricsGap,
            0
        )
        return min(
            max(availableHeight / 5, Self.minimumLyricSlotHeight),
            Self.maximumLyricSlotHeight
        )
    }

    var modeLyricsFrame: CGRect {
        let width = min(
            max(canvasSize.width - Self.outerMargin * 2, 0),
            760
        )
        return CGRect(
            x: (canvasSize.width - width) * 0.5,
            y: modeArtworkFrame.maxY + Self.lyricsGap,
            width: width,
            height: modeLyricSlotHeight * 5
        )
    }

    func emitterOrigin(
        lane: RhythmLane,
        isCadenceModeActive: Bool
    ) -> CGPoint {
        let frame = isCadenceModeActive
            ? modeArtworkFrame
            : standardArtworkFrame
        let horizontalPosition: CGFloat = lane == .left ? 0.06 : 0.94
        return CGPoint(
            x: frame.minX + frame.width * horizontalPosition,
            y: frame.midY
        )
    }

    func normalizedEmitterOrigin(
        lane: RhythmLane,
        isCadenceModeActive: Bool
    ) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return .zero
        }
        let origin = emitterOrigin(lane: lane, isCadenceModeActive: isCadenceModeActive)
        return CGPoint(
            x: origin.x / canvasSize.width,
            y: origin.y / canvasSize.height
        )
    }
}
