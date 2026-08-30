import AppKit

typealias NativeTrackArtworkLoader = @MainActor @Sendable (
    UUID,
    ArtworkAssetVariant
) async -> ArtworkAsset?

enum NativeTrackTableAction: Equatable, Sendable {
    case select
    case play
    case favorite
    case artist
    case album
}

enum NativeTrackTableChromeTone: Equatable, Sendable {
    case clear
    case selection
    case hover
    case primary
    case secondary
    case tertiary
}

struct NativeTrackTableChromePresentation: Equatable, Sendable {
    let fill: NativeTrackTableChromeTone
    let outline: NativeTrackTableChromeTone
    let favorite: NativeTrackTableChromeTone
    let action: NativeTrackTableChromeTone

    static func resolve(
        isSelected: Bool,
        isFocused _: Bool,
        isHovered: Bool,
        isLiveScrolling _: Bool,
        isFavorite: Bool
    ) -> NativeTrackTableChromePresentation {
        NativeTrackTableChromePresentation(
            fill: isSelected
                ? .selection
                : isHovered ? .hover : .clear,
            outline: .clear,
            favorite: isFavorite ? .primary : .secondary,
            action: isHovered ? .primary : .tertiary
        )
    }
}
