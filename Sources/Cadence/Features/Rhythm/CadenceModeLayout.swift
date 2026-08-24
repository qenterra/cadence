import CoreGraphics

struct CadenceModeLayout: Hashable, Sendable {
    private static let outerMargin: CGFloat = 24
    private static let standardInset: CGFloat = 42
    private static let contentGap: CGFloat = 16
    private static let identityHeight: CGFloat = 56
    private static let minimumLyricSlotHeight: CGFloat = 32
    private static let maximumLyricSlotHeight: CGFloat = 52
    private static let maximumModeArtworkSize: CGFloat = 560

    let canvasSize: CGSize
    let contextWidth: CGFloat
    let options: CadenceModeOptions

    init(
        canvasSize: CGSize,
        contextWidth: CGFloat,
        options: CadenceModeOptions = .default
    ) {
        self.canvasSize = canvasSize
        self.contextWidth = contextWidth
        self.options = options
    }

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
        let size = max(
            min(
                Self.maximumModeArtworkSize,
                canvasSize.width * 0.36,
                availableHeight - minimumLowerContentHeight
            ),
            0
        )
        let compositionHeight = size
            + lowerContentHeight(forArtworkSize: size)
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
        guard options.showsLyrics else {
            return 0
        }
        return modeLyricSlotHeight(forArtworkSize: modeArtworkFrame.height)
    }

    private func modeLyricSlotHeight(
        forArtworkSize artworkSize: CGFloat
    ) -> CGFloat {
        let availableHeight = max(
            canvasSize.height - Self.outerMargin * 2
                - artworkSize - fixedLowerContentHeight,
            0
        )
        return min(
            max(availableHeight / 5, Self.minimumLyricSlotHeight),
            Self.maximumLyricSlotHeight
        )
    }

    var modeIdentityFrame: CGRect? {
        guard options.showsTrackInformation else {
            return nil
        }
        let width = min(
            max(canvasSize.width - Self.outerMargin * 2, 0),
            640
        )
        return CGRect(
            x: (canvasSize.width - width) * 0.5,
            y: modeArtworkFrame.maxY + Self.contentGap,
            width: width,
            height: Self.identityHeight
        )
    }

    var modeLyricsFrame: CGRect? {
        guard options.showsLyrics else {
            return nil
        }
        let width = min(
            max(canvasSize.width - Self.outerMargin * 2, 0),
            760
        )
        let originY: CGFloat = if let identityFrame = modeIdentityFrame {
            identityFrame.maxY + Self.contentGap
        } else {
            modeArtworkFrame.maxY + Self.contentGap
        }
        return CGRect(
            x: (canvasSize.width - width) * 0.5,
            y: originY,
            width: width,
            height: modeLyricSlotHeight * 5
        )
    }

    private var lowerSectionCount: Int {
        (options.showsTrackInformation ? 1 : 0)
            + (options.showsLyrics ? 1 : 0)
    }

    private var minimumLowerContentHeight: CGFloat {
        fixedLowerContentHeight
            + (options.showsLyrics
                ? Self.minimumLyricSlotHeight * 5
                : 0)
    }

    private var fixedLowerContentHeight: CGFloat {
        CGFloat(lowerSectionCount) * Self.contentGap
            + (options.showsTrackInformation ? Self.identityHeight : 0)
    }

    private func lowerContentHeight(
        forArtworkSize artworkSize: CGFloat
    ) -> CGFloat {
        fixedLowerContentHeight
            + (options.showsLyrics
                ? modeLyricSlotHeight(forArtworkSize: artworkSize) * 5
                : 0)
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
