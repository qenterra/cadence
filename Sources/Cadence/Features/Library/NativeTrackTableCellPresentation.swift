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
