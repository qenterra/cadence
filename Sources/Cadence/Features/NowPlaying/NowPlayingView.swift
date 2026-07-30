import SwiftUI

struct NowPlayingView: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if let track = model.currentTrack {
                let layout = NowPlayingLayoutMetrics(
                    totalWidth: geometry.size.width
                )

                HStack(spacing: 0) {
                    NowPlayingTrackContext(
                        model: model,
                        track: track,
                        artworkSize: layout.artworkSize
                    )
                    .frame(width: layout.contextWidth)

                    Rectangle()
                        .fill(CadenceTheme.separator)
                        .frame(width: 1)

                    panel
                        .frame(width: layout.panelWidth)
                }
                .background {
                    ArtworkHaze(
                        palette: model.resolvedArtwork(for: track).palette
                    )
                    .allowsHitTesting(false)
                }
                .transition(.opacity)
            } else if let track = model.currentPlaybackTrack {
                ProductionNowPlayingView(
                    model: model,
                    track: track
                )
                .transition(.opacity)
            } else {
                ContentUnavailableView {
                    Label("Nothing Playing", systemImage: "music.note")
                } description: {
                    Text("Start a track to open Now Playing.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CadenceTheme.contentBackground)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.15),
            value: model.currentTrackID
        )
        .onExitCommand {
            model.dismissNowPlaying()
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.selectedNowPlayingPanel.title)
                    .font(.title2.weight(.semibold))

                Spacer()

                NowPlayingPanelPicker(model: model)
            }
            .padding(.horizontal, 28)
            .frame(height: 76)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            Group {
                switch model.selectedNowPlayingPanel {
                case .lyrics:
                    LyricsPanel(model: model)
                case .queue:
                    PlaybackQueuePanel(model: model)
                }
            }
            .id(model.selectedNowPlayingPanel)
            .transition(.opacity)
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.13),
            value: model.selectedNowPlayingPanel
        )
    }
}
