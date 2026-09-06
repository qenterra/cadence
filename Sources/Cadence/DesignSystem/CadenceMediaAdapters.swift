import QenTerraMediaComponents
import SwiftUI

extension ArtworkPalette {
    var designSystemPalette: QenTerraMediaComponents.ArtworkPalette {
        let values: (Color, Color, String) = switch self {
        case .amberNoir:
            (Color(red: 0.08, green: 0.06, blue: 0.04), Color(red: 0.75, green: 0.42, blue: 0.12), "waveform")
        case .arctic:
            (Color(red: 0.10, green: 0.20, blue: 0.30), Color(red: 0.62, green: 0.86, blue: 0.94), "snowflake")
        case .blueHour:
            (Color(red: 0.03, green: 0.08, blue: 0.18), Color(red: 0.14, green: 0.38, blue: 0.74), "moonphase.waning.crescent")
        case .ember:
            (Color(red: 0.12, green: 0.03, blue: 0.03), Color(red: 0.86, green: 0.24, blue: 0.10), "sparkles")
        case .forest:
            (Color(red: 0.03, green: 0.12, blue: 0.09), Color(red: 0.26, green: 0.58, blue: 0.38), "leaf")
        case .lilac:
            (Color(red: 0.15, green: 0.10, blue: 0.22), Color(red: 0.58, green: 0.42, blue: 0.72), "circle.hexagongrid")
        case .ocean:
            (Color(red: 0.02, green: 0.13, blue: 0.18), Color(red: 0.08, green: 0.52, blue: 0.64), "water.waves")
        case .rose:
            (Color(red: 0.18, green: 0.06, blue: 0.10), Color(red: 0.74, green: 0.27, blue: 0.40), "camera.macro")
        case .silver:
            (Color(red: 0.12, green: 0.13, blue: 0.15), Color(red: 0.60, green: 0.64, blue: 0.68), "circle.grid.cross")
        case .sunset:
            (Color(red: 0.18, green: 0.06, blue: 0.16), Color(red: 0.92, green: 0.38, blue: 0.20), "sun.horizon")
        }
        return QenTerraMediaComponents.ArtworkPalette(
            leading: values.0,
            trailing: values.1,
            highlight: values.1,
            symbolName: values.2
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
