import AppKit

enum NativeFavoriteVisibility: Equatable, Sendable {
    case hidden
    case emptySecondary
    case filledPrimary

    static func resolve(
        isFavorite: Bool,
        isHovered: Bool,
        isLiveScrolling _: Bool
    ) -> NativeFavoriteVisibility {
        if isFavorite {
            return .filledPrimary
        }
        return isHovered ? .emptySecondary : .hidden
    }
}

struct NativeTrackRowGeometry: Equatable, Sendable {
    let contentBounds: CGRect
    let twoLineBounds: CGRect
    let titleFrame: CGRect
    let artistFrame: CGRect
    let singleLineFrame: CGRect

    init(rowHeight: CGFloat) {
        let lineHeight: CGFloat = 19
        let lineGap: CGFloat = 2
        let stackHeight = lineHeight * 2 + lineGap
        let stackY = (rowHeight - stackHeight) / 2
        contentBounds = CGRect(
            x: 0,
            y: 0,
            width: 0,
            height: rowHeight
        )
        artistFrame = CGRect(
            x: 0,
            y: stackY,
            width: 0,
            height: lineHeight
        )
        titleFrame = CGRect(
            x: 0,
            y: stackY + lineHeight + lineGap,
            width: 0,
            height: lineHeight
        )
        twoLineBounds = CGRect(
            x: 0,
            y: stackY,
            width: 0,
            height: stackHeight
        )
        singleLineFrame = CGRect(
            x: 0,
            y: (rowHeight - lineHeight) / 2,
            width: 0,
            height: lineHeight
        )
    }
}

struct NativeTrackRowHorizontalGeometry: Equatable, Sendable {
    static let artworkSize: CGFloat = 40

    let artworkFrame: CGRect?
    let songOriginX: CGFloat

    init(
        rowHeight: CGFloat,
        leadingX: CGFloat,
        showsArtwork: Bool
    ) {
        guard showsArtwork else {
            artworkFrame = nil
            songOriginX = leadingX
            return
        }
        artworkFrame = CGRect(
            x: leadingX,
            y: (rowHeight - Self.artworkSize) / 2,
            width: Self.artworkSize,
            height: Self.artworkSize
        )
        songOriginX = leadingX
            + Self.artworkSize
            + TrackTableColumnPolicy.songContentSpacing
    }
}

struct TrackTableSelectionModifiers: Equatable, Sendable {
    let isRange: Bool
    let isAdditive: Bool

    init(_ flags: NSEvent.ModifierFlags) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        isRange = flags.contains(.shift)
        isAdditive = flags.contains(.command) || flags.contains(.control)
    }
}

enum TrackTableContextSelection {
    static func resolve(
        clickedRow: Int,
        selectedRows: IndexSet,
        modifiers: TrackTableSelectionModifiers
    ) -> IndexSet {
        if modifiers.isAdditive {
            var result = selectedRows
            result.formSymmetricDifference(IndexSet(integer: clickedRow))
            return result
        }
        return selectedRows.contains(clickedRow)
            ? selectedRows
            : IndexSet(integer: clickedRow)
    }
}
