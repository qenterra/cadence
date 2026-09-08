import QenTerraMediaComponents
import SwiftUI

extension ArtworkPalette {
    var designSystemPalette: QenTerraMediaComponents.ArtworkPalette {
        let leading: Color
        let trailing: Color
        let symbolName: String

        switch self {
        case .amberNoir:
            leading = Color(red: 0.08, green: 0.06, blue: 0.04)
            trailing = Color(red: 0.75, green: 0.42, blue: 0.12)
            symbolName = "waveform"
        case .arctic:
            leading = Color(red: 0.10, green: 0.20, blue: 0.30)
            trailing = Color(red: 0.62, green: 0.86, blue: 0.94)
            symbolName = "snowflake"
        case .blueHour:
            leading = Color(red: 0.03, green: 0.08, blue: 0.18)
            trailing = Color(red: 0.14, green: 0.38, blue: 0.74)
            symbolName = "moonphase.waning.crescent"
        case .ember:
            leading = Color(red: 0.12, green: 0.03, blue: 0.03)
            trailing = Color(red: 0.86, green: 0.24, blue: 0.10)
            symbolName = "sparkles"
        case .forest:
            leading = Color(red: 0.03, green: 0.12, blue: 0.09)
            trailing = Color(red: 0.26, green: 0.58, blue: 0.38)
            symbolName = "leaf"
        case .lilac:
            leading = Color(red: 0.15, green: 0.10, blue: 0.22)
            trailing = Color(red: 0.58, green: 0.42, blue: 0.72)
            symbolName = "circle.hexagongrid"
        case .ocean:
            leading = Color(red: 0.02, green: 0.13, blue: 0.18)
            trailing = Color(red: 0.08, green: 0.52, blue: 0.64)
            symbolName = "water.waves"
        case .rose:
            leading = Color(red: 0.18, green: 0.06, blue: 0.10)
            trailing = Color(red: 0.74, green: 0.27, blue: 0.40)
            symbolName = "camera.macro"
        case .silver:
            leading = Color(red: 0.12, green: 0.13, blue: 0.15)
            trailing = Color(red: 0.60, green: 0.64, blue: 0.68)
            symbolName = "circle.grid.cross"
        case .sunset:
            leading = Color(red: 0.18, green: 0.06, blue: 0.16)
            trailing = Color(red: 0.92, green: 0.38, blue: 0.20)
            symbolName = "sun.horizon"
        }
        return QenTerraMediaComponents.ArtworkPalette(
            leading: leading,
            trailing: trailing,
            highlight: trailing,
            symbolName: symbolName
        )
    }
}

extension ArtworkPlaceholder {
    var designSystemKind: ArtworkPlaceholderKind {
        switch self {
        case .artist: .artist
        case .album: .album
        case .track: .track
        case .playlist: .playlist
        case .smartCollection: .collection
        }
    }
}

enum CadenceMediaAdapters {
    static func artworkState(
        for source: ResolvedArtworkSource
    ) -> ArtworkPresentationState {
        switch source {
        case .catalog, .custom:
            .content
        case let .placeholder(kind):
            .placeholder(kind.designSystemKind)
        }
    }

    static func mediaItem(
        _ projection: TrackRowDisplayProjection,
        isSelected: Bool,
        isAvailable: Bool = true
    ) -> MediaItemPresentation<UUID> {
        MediaItemPresentation(
            id: projection.id,
            title: projection.title,
            subtitle: projection.artist,
            metadata: "\(projection.album) · \(projection.duration)",
            isSelected: isSelected,
            isCurrent: projection.isCurrentTrack,
            isPlaying: projection.isPlaying,
            isAvailable: isAvailable
        )
    }

    static func mediaItem(
        id: UUID,
        title: String,
        subtitle: String,
        metadata: String? = nil,
        isSelected: Bool = false,
        isCurrent: Bool = false,
        isPlaying: Bool = false,
        isAvailable: Bool = true
    ) -> MediaItemPresentation<UUID> {
        MediaItemPresentation(
            id: id,
            title: title,
            subtitle: subtitle,
            metadata: metadata,
            isSelected: isSelected,
            isCurrent: isCurrent,
            isPlaying: isPlaying,
            isAvailable: isAvailable
        )
    }
}
