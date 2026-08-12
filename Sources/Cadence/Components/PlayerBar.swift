import SwiftUI

struct PlayerBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var model: CadenceAppModel
    let suspendsProgressAnimation: Bool
    @State private var pendingSeekProgress: Double?
    @State private var isArtworkHovered = false

    var body: some View {
        HStack(spacing: 24) {
            nowPlaying
                .frame(width: 244, alignment: .leading)

            transport
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

            outputControls
                .frame(width: 244, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 96)
        .cadenceGlassSurface(cornerRadius: CadenceTheme.radiusNone)
    }
}

private struct PlaybackProgressControl: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var model: CadenceAppModel
    @Binding var pendingSeekProgress: Double?
    let suspendsProgressAnimation: Bool

    var body: some View {
        HStack(spacing: 8) {
            if suspendsProgressAnimation {
                Text(elapsedText)
            } else {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text(elapsedText)
                }
            }
            Slider(
                value: progressBinding,
                in: 0 ... 1
            ) { isEditing in
                commitSeekWhenNeeded(isEditing: isEditing)
            }
            .tint(.primary)
            .accessibilityLabel("Playback progress")
            .disabled(!model.hasCurrentPlaybackItem)
            Text(durationText)
        }
        .frame(minWidth: 220, idealWidth: 300, maxWidth: 360)
        .font(.caption2)
        .foregroundStyle(secondaryTextColor)
        .monospacedDigit()
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.secondary
    }

    private var elapsedText: String {
        guard model.hasCurrentPlaybackItem else {
            return "0:00"
        }
        let time = pendingSeekProgress.map {
            model.playbackDuration * $0
        } ?? model.playbackPresentationTime()
        return TrackPreview.timeText(time)
    }

    private var durationText: String {
        guard model.hasCurrentPlaybackItem else {
            return "0:00"
        }
        return TrackPreview.timeText(model.playbackDuration)
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: {
                if let pendingSeekProgress {
                    return pendingSeekProgress
                }
                let duration = model.playbackDuration
                guard duration > 0 else {
                    return 0
                }
                return min(
                    max(model.playbackPresentationTime() / duration, 0),
                    1
                )
            },
            set: { pendingSeekProgress = $0 }
        )
    }

    private func commitSeekWhenNeeded(
        isEditing: Bool
    ) {
        guard !isEditing, let pendingSeekProgress else {
            return
        }
        Task { @MainActor in
            await model.seekPlayback(toProgress: pendingSeekProgress)
            if self.pendingSeekProgress == pendingSeekProgress {
                self.pendingSeekProgress = nil
            }
        }
    }
}

private extension PlayerBar {
    @ViewBuilder
    private var nowPlaying: some View {
        if let track = model.currentPlaybackTrack {
            HStack(spacing: 11) {
                Button {
                    model.presentNowPlaying()
                } label: {
                    ProductionArtworkView(
                        model: model,
                        artworkID: track.artworkID,
                        title: track.title,
                        placeholder: .track,
                        cornerRadius: CadenceTheme.radiusControl
                    )
                    .frame(width: 56, height: 56)
                    .overlay {
                        if isArtworkHovered {
                            RoundedRectangle(
                                cornerRadius: CadenceTheme.radiusControl,
                                style: .continuous
                            )
                            .fill(.black.opacity(0.36))

                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .symbolEffect(.bounce, value: isArtworkHovered)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { isArtworkHovered = $0 }
                .help("Show Now Playing")
                .accessibilityLabel(
                    "Show Now Playing for \(track.title) by \(track.artist)"
                )

                playbackLabels(
                    title: track.title,
                    artist: track.artist
                )

                if model.isCurrentPlaybackExternal {
                    Button("Add to Library…", systemImage: "plus.rectangle.on.folder") {
                        model.addCurrentExternalAudioToLibrary()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(CadenceRowButtonStyle())
                    .help("Add to Library…")
                    .accessibilityLabel("Add \(track.title) to Library")
                } else {
                    FavoriteButton(
                        isFavorite: model.currentProductionTrackIsFavorite,
                        itemName: track.title
                    ) { requestedValue in
                        await model.setCurrentProductionTrackFavorite(
                            requestedValue
                        )
                    }
                }

                Spacer(minLength: 0)
            }
        } else {
            emptyPlaybackGuidance
        }
    }

    private var transport: some View {
        HStack(spacing: 18) {
            HStack(spacing: 16) {
                controlButton(
                    symbol: "shuffle",
                    label: "Shuffle",
                    isActive: model.isShuffleEnabled,
                    isEnabled: hasPlaybackItem
                ) {
                    model.isShuffleEnabled.toggle()
                }

                controlButton(
                    symbol: "backward.fill",
                    label: "Previous",
                    isEnabled: hasPlaybackItem
                ) {
                    model.selectPreviousTrack()
                }

                Button {
                    model.togglePlayback()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(CadenceTheme.contentBackground)
                        .background(CadenceTheme.primaryAccent, in: Circle())
                }
                .buttonStyle(CadenceRowButtonStyle())
                .help(model.isPlaying ? "Pause" : "Play")
                .disabled(!hasPlaybackItem)

                controlButton(
                    symbol: "forward.fill",
                    label: "Next",
                    isEnabled: hasPlaybackItem
                ) {
                    model.selectNextTrack()
                }

                controlButton(
                    symbol: model.repeatMode.symbolName,
                    label: repeatLabel,
                    isActive: model.repeatMode != .off,
                    isEnabled: hasPlaybackItem
                ) {
                    model.cycleRepeatMode()
                }
            }

            PlaybackProgressControl(
                model: model,
                pendingSeekProgress: $pendingSeekProgress,
                suspendsProgressAnimation: suspendsProgressAnimation
            )
        }
    }

    private var outputControls: some View {
        HStack(spacing: 12) {
            playbackFailureMenu

            Button {
                model.toggleMute()
            } label: {
                Image(systemName: volumeSymbol)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(CadenceRowButtonStyle())
            .help(model.volume > 0 ? "Mute" : "Unmute")
            .accessibilityLabel(model.volume > 0 ? "Mute" : "Unmute")

            Slider(value: volumeBinding, in: 0 ... 1)
                .frame(width: 86)
                .accessibilityLabel("Volume")

            audioOutputMenu
            controlButton(
                symbol: "list.bullet",
                label: "Queue",
                isActive: isQueuePresented,
                isEnabled: hasPlaybackItem
            ) {
                model.presentPlaybackQueue()
            }
        }
    }

    private var hasPlaybackItem: Bool {
        model.hasCurrentPlaybackItem
    }

    private var repeatLabel: String {
        switch model.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    private var volumeSymbol: String {
        switch model.volume {
        case ...0:
            "speaker.slash.fill"
        case ..<0.34:
            "speaker.wave.1.fill"
        case ..<0.67:
            "speaker.wave.2.fill"
        default:
            "speaker.wave.3.fill"
        }
    }

    private var isQueuePresented: Bool {
        model.playbackWorkspace == .nowPlaying
            && model.selectedNowPlayingPanel == .queue
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { model.volume },
            set: { model.volume = $0 }
        )
    }

    private func controlButton(
        symbol: String,
        label: String,
        isActive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolVariant(isActive ? .fill : .none)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 34, height: 34)
                .background {
                    if isActive {
                        RoundedRectangle(
                            cornerRadius: CadenceTheme.radiusControl,
                            style: .continuous
                        )
                        .fill(CadenceTheme.selectionFill)
                    }
                }
        }
        .buttonStyle(CadenceRowButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .disabled(!isEnabled)
    }

    private func playbackLabels(
        title: String,
        artist: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
            Text(artist)
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
        }
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.68) : Color.secondary
    }
}
