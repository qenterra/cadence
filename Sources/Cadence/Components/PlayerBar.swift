import SwiftUI

struct PlayerBar: View {
    @Bindable var model: CadenceAppModel
    @State private var pendingSeekProgress: Double?
    @State private var isQualityProfilePresented = false

    var body: some View {
        HStack(spacing: 24) {
            nowPlaying
                .frame(width: 224, alignment: .leading)

            transport
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                .guideAnchor(.playerBar)

            outputControls
                .frame(width: 244, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 96)
        .cadenceGlassSurface(cornerRadius: 0)
    }
}

private extension PlayerBar {
    @ViewBuilder
    private var nowPlaying: some View {
        if let track = model.currentPlaybackTrack {
            Button {
                model.presentNowPlaying()
            } label: {
                HStack(spacing: 11) {
                    ProductionArtworkView(
                        model: model,
                        artworkID: productionArtworkID(for: track),
                        title: track.title,
                        placeholder: .track,
                        cornerRadius: 7
                    )
                    .frame(width: 56, height: 56)

                    playbackLabels(
                        title: track.title,
                        artist: track.artist
                    )

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(CadenceRowButtonStyle())
            .help("Show Now Playing")
            .accessibilityLabel(
                "Show Now Playing for \(track.title) by \(track.artist)"
            )
        } else if let track = model.currentTrack {
            Button {
                model.presentNowPlaying()
            } label: {
                HStack(spacing: 11) {
                    MediaArtworkView(
                        source: model.resolvedArtwork(for: track),
                        title: track.title,
                        placeholder: .track,
                        cornerRadius: 7
                    )
                    .frame(width: 56, height: 56)

                    playbackLabels(
                        title: track.title,
                        artist: track.artist
                    )

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
                        .foregroundStyle(CadenceTheme.contentBackground)
                        .background(CadenceTheme.primaryAccent, in: Circle())
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
                Slider(
                    value: playbackProgress,
                    in: 0 ... 1
                ) { isEditing in
                    guard
                        !isEditing,
                        let pendingSeekProgress
                    else {
                        return
                    }
                    Task { @MainActor in
                        await model.seekPlayback(
                            toProgress: pendingSeekProgress
                        )
                        if self.pendingSeekProgress
                            == pendingSeekProgress {
                            self.pendingSeekProgress = nil
                        }
                    }
                }
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
            if let failure = model.playbackCoordinator?.state.failure {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help(failure.message)
                    .accessibilityLabel(
                        "Playback error: \(failure.message)"
                    )
            }

            Image(systemName: volumeSymbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Slider(value: volumeBinding, in: 0 ... 1)
                .frame(width: 86)
                .accessibilityLabel("Volume")

            controlButton(symbol: "airplayaudio", label: "Audio Output") {}
            qualityProfileMenu
            controlButton(
                symbol: "list.bullet",
                label: "Queue",
                isActive: isQueuePresented
            ) {
                model.presentPlaybackQueue()
            }
        }
    }

    private var elapsedText: String {
        guard model.hasCurrentPlaybackItem else {
            return "0:00"
        }
        let time = pendingSeekProgress.map {
            model.playbackDuration * $0
        } ?? model.playbackCurrentTime
        return TrackPreview.timeText(time)
    }

    private var durationText: String {
        guard model.hasCurrentPlaybackItem else {
            return "0:00"
        }
        return TrackPreview.timeText(model.playbackDuration)
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

    private var playbackProgress: Binding<Double> {
        Binding(
            get: {
                pendingSeekProgress ?? model.progress
            },
            set: {
                pendingSeekProgress = $0
            }
        )
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
                            cornerRadius: 9,
                            style: .continuous
                        )
                        .fill(CadenceTheme.selectionFill)
                    }
                }
        }
        .buttonStyle(CadenceRowButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private func playbackLabels(
        title: String,
        artist: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func productionArtworkID(
        for track: PlaybackTrack
    ) -> UUID? {
        model.librarySession.store.tracks.first {
            $0.id == track.id
        }?.artworkID ?? track.artworkID
    }
}

private extension PlayerBar {
    var qualityProfileMenu: some View {
        Button {
            isQualityProfilePresented.toggle()
        } label: {
            Image(systemName: "waveform.badge.magnifyingglass")
                .foregroundStyle(
                    isQualityProfilePresented ? .primary : .secondary
                )
                .frame(width: 34, height: 34)
                .background {
                    if isQualityProfilePresented {
                        RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                        .fill(CadenceTheme.selectionFill)
                    }
                }
        }
        .buttonStyle(CadenceRowButtonStyle())
        .popover(
            isPresented: $isQualityProfilePresented,
            arrowEdge: .bottom
        ) {
            qualityProfilePopover
        }
        .help("Quality Profile: \(model.qualityProfile.title)")
        .accessibilityLabel(
            "Quality Profile, \(model.qualityProfile.title)"
        )
    }

    var qualityProfilePopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quality Profile")
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(AudioQualityProfile.allCases) { profile in
                Button {
                    model.selectQualityProfile(profile)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .opacity(model.qualityProfile == profile ? 1 : 0)
                            .frame(width: 14)
                        Text(profile.title)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(CadenceMenuRowButtonStyle())
            }

            Divider()
                .padding(.vertical, 4)

            Toggle(
                "Spatialize Stereo",
                isOn: $model.isStereoSpatializationEnabled
            )
            .disabled(model.qualityProfile != .immersive)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .padding(6)
        .frame(width: 220)
    }
}
