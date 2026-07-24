import SwiftUI

struct PlayerBar: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        HStack(spacing: 24) {
            nowPlaying
                .frame(width: 224, alignment: .leading)

            transport
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

            outputControls
                .frame(width: 216, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 96)
        .cadenceGlassSurface(cornerRadius: 0)
    }

    @ViewBuilder
    private var nowPlaying: some View {
        if let track = model.currentTrack {
            Button {
                model.presentNowPlaying()
            } label: {
                HStack(spacing: 11) {
                    ArtworkView(
                        palette: track.artworkPalette,
                        title: track.title,
                        cornerRadius: 7
                    )
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(CadenceRowButtonStyle())
            .help("Show Now Playing")
            .accessibilityLabel(
                "Show Now Playing for \(track.title) by \(track.artist)"
            )
        } else {
            Label("Nothing Playing", systemImage: "music.note")
                .foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        HStack(spacing: 18) {
            HStack(spacing: 16) {
                controlButton(
                    symbol: "shuffle",
                    label: "Shuffle",
                    isActive: model.isShuffleEnabled
                ) {
                    model.isShuffleEnabled.toggle()
                }

                controlButton(symbol: "backward.fill", label: "Previous") {
                    model.selectPreviousTrack()
                }

                Button {
                    model.togglePlayback()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(.black)
                        .background(.white, in: Circle())
                }
                .buttonStyle(CadenceRowButtonStyle())
                .help(model.isPlaying ? "Pause" : "Play")

                controlButton(symbol: "forward.fill", label: "Next") {
                    model.selectNextTrack()
                }

                controlButton(
                    symbol: model.repeatMode.symbolName,
                    label: repeatLabel,
                    isActive: model.repeatMode != .off
                ) {
                    model.cycleRepeatMode()
                }
            }

            HStack(spacing: 8) {
                Text(elapsedText)
                Slider(value: $model.progress, in: 0 ... 1)
                    .tint(.primary)
                    .accessibilityLabel("Playback progress")
                Text(durationText)
            }
            .frame(minWidth: 220, idealWidth: 300, maxWidth: 360)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var outputControls: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Slider(value: $model.volume, in: 0 ... 1)
                .frame(width: 86)
                .accessibilityLabel("Volume")

            controlButton(symbol: "airplayaudio", label: "Audio Output") {}
            controlButton(symbol: "list.bullet", label: "Queue") {
                model.presentPlaybackQueue()
            }
        }
    }

    private var elapsedText: String {
        guard let track = model.currentTrack else {
            return "0:00"
        }
        return TrackPreview.timeText(track.duration * model.progress)
    }

    private var durationText: String {
        guard let track = model.currentTrack else {
            return "0:00"
        }
        return track.durationText
    }

    private var repeatLabel: String {
        switch model.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    private func controlButton(
        symbol: String,
        label: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolVariant(isActive ? .fill : .none)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(CadenceRowButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}
