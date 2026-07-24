import SwiftUI

struct ArtworkView: View {
    let palette: ArtworkPalette
    let title: String
    var cornerRadius: CGFloat = 8
    var showsBorder = true
    var fillsAvailableSpace = false

    var body: some View {
        if fillsAvailableSpace {
            artwork
        } else {
            artwork
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private var artwork: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: palette.colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(palette.highlight.opacity(0.52))
                    .frame(
                        width: geometry.size.width * 0.72,
                        height: geometry.size.height * 0.72
                    )
                    .blur(radius: geometry.size.width * 0.12)
                    .offset(
                        x: geometry.size.width * 0.2,
                        y: -geometry.size.height * 0.18
                    )

                LinearGradient(
                    colors: [.clear, .black.opacity(0.42)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Image(systemName: palette.symbolName)
                    .font(.system(size: symbolSize(for: geometry.size), weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.62))
                    .symbolRenderingMode(.hierarchical)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Artwork for \(title)")
    }

    private func symbolSize(for size: CGSize) -> CGFloat {
        min(max(size.width * 0.18, 10), 34)
    }
}

struct ArtistArtworkView: View {
    let artist: ArtistPreview

    var body: some View {
        ArtworkView(
            palette: artist.artworkPalette,
            title: artist.name,
            cornerRadius: 100
        )
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityLabel("Artwork for \(artist.name)")
    }
}

private extension ArtworkPalette {
    var colors: [Color] {
        switch self {
        case .amberNoir: [Color(red: 0.08, green: 0.06, blue: 0.04), Color(red: 0.75, green: 0.42, blue: 0.12)]
        case .arctic: [Color(red: 0.10, green: 0.20, blue: 0.30), Color(red: 0.62, green: 0.86, blue: 0.94)]
        case .blueHour: [Color(red: 0.03, green: 0.08, blue: 0.18), Color(red: 0.14, green: 0.38, blue: 0.74)]
        case .ember: [Color(red: 0.12, green: 0.03, blue: 0.03), Color(red: 0.86, green: 0.24, blue: 0.10)]
        case .forest: [Color(red: 0.03, green: 0.12, blue: 0.09), Color(red: 0.26, green: 0.58, blue: 0.38)]
        case .lilac: [Color(red: 0.15, green: 0.10, blue: 0.22), Color(red: 0.58, green: 0.42, blue: 0.72)]
        case .ocean: [Color(red: 0.02, green: 0.13, blue: 0.18), Color(red: 0.08, green: 0.52, blue: 0.64)]
        case .rose: [Color(red: 0.18, green: 0.06, blue: 0.10), Color(red: 0.74, green: 0.27, blue: 0.40)]
        case .silver: [Color(red: 0.12, green: 0.13, blue: 0.15), Color(red: 0.60, green: 0.64, blue: 0.68)]
        case .sunset: [Color(red: 0.18, green: 0.06, blue: 0.16), Color(red: 0.92, green: 0.38, blue: 0.20)]
        }
    }

    var highlight: Color {
        colors.last ?? .white
    }

    var symbolName: String {
        switch self {
        case .amberNoir: "waveform"
        case .arctic: "snowflake"
        case .blueHour: "moonphase.waning.crescent"
        case .ember: "sparkles"
        case .forest: "leaf"
        case .lilac: "circle.hexagongrid"
        case .ocean: "water.waves"
        case .rose: "camera.macro"
        case .silver: "circle.grid.cross"
        case .sunset: "sun.horizon"
        }
    }
}
