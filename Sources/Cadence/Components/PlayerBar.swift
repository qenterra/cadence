import SwiftUI

enum PlayerBarLayoutMetrics {
    static let height: CGFloat = 96
    static let horizontalInset = CadenceLayout.panelInset
    static let regionSpacing = CadenceLayout.pageInset
    static let controlSpacing = CadenceLayout.contentGap
    static let transportSpacing = CadenceLayout.controlGap
    static let metadataSpacing = CadenceLayout.textStack
}

struct PlayerBar: View {
    @Environment(\.visualRegressionUsesStableSystemControls)
    var usesStableSystemControls
    @Bindable var model: CadenceAppModel
    let suspendsProgressAnimation: Bool
    @State private var pendingSeekProgress: Double?
    @State private var isArtworkHovered = false

    var body: some View {
        HStack(spacing: PlayerBarLayoutMetrics.regionSpacing) {
            nowPlaying
                .frame(width: 244, alignment: .leading)

            transport
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

            outputControls
                .frame(width: 244, alignment: .trailing)
        }
        .padding(.horizontal, PlayerBarLayoutMetrics.horizontalInset)
        .frame(height: PlayerBarLayoutMetrics.height)
        .cadenceGlassSurface(cornerRadius: CadenceTheme.radiusNone)
    }
}

private struct PlaybackProgressControl: View {
    @Bindable var model: CadenceAppModel
    @Binding var pendingSeekProgress: Double?
    let suspendsProgressAnimation: Bool

    var body: some View {
        HStack(spacing: CadenceLayout.compactGap) {
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
            .accessibilityLabel(accessibility.label)
            .disabled(!accessibility.isEnabled)
            Text(durationText)
        }
        .frame(minWidth: 220, idealWidth: 300, maxWidth: 360)
        .font(.caption2)
        .foregroundStyle(CadenceTheme.playerMetadata)
        .monospacedDigit()
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

    private var accessibility: PlayerBarAccessibilityControl {
        PlayerBarAccessibilityContract.control(
            .progress,
            hasPlaybackItem: model.hasCurrentPlaybackItem,
            isPlaying: model.isPlaying,
            repeatMode: model.repeatMode
        )
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
            HStack(spacing: CadenceLayout.controlGap) {
                Button {
                    model.presentNowPlaying(panel: .lyrics)
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
                        itemID: track.id,
                        isFavorite: model.currentProductionTrackIsFavorite,
                        itemName: track.title
                    ) { requestedValue in
                        await model.setProductionPlaybackTrackFavorite(
                            id: track.id,
                            isFavorite: requestedValue
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
        HStack(spacing: PlayerBarLayoutMetrics.controlSpacing) {
            HStack(spacing: PlayerBarLayoutMetrics.transportSpacing) {
                controlButton(
                    symbol: "shuffle",
                    label: accessibility(for: .shuffle).label,
                    isActive: model.isShuffleEnabled,
                    isEnabled: accessibility(for: .shuffle).isEnabled
                ) {
                    model.isShuffleEnabled.toggle()
                }

                controlButton(
                    symbol: "backward.fill",
                    label: accessibility(for: .previous).label,
                    isEnabled: accessibility(for: .previous).isEnabled
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
                        .background(primaryControlFill, in: Circle())
                }
                .buttonStyle(CadenceRowButtonStyle())
                .help(accessibility(for: .playPause).label)
                .accessibilityLabel(accessibility(for: .playPause).label)
                .disabled(!accessibility(for: .playPause).isEnabled)

                controlButton(
                    symbol: "forward.fill",
                    label: accessibility(for: .next).label,
                    isEnabled: accessibility(for: .next).isEnabled
                ) {
                    model.selectNextTrack()
                }

                controlButton(
                    symbol: model.repeatMode.symbolName,
                    label: accessibility(for: .repeatMode).label,
                    isActive: model.repeatMode != .off,
                    isEnabled: accessibility(for: .repeatMode).isEnabled
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
        HStack(spacing: CadenceLayout.controlGap) {
            playbackFailureMenu

            Button {
                model.toggleMute()
            } label: {
                Image(systemName: volumeSymbol)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(
                        CadenceTheme.playerControl(.normal)
                    )
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
                label: accessibility(for: .queue).label,
                isActive: isQueuePresented,
                isEnabled: accessibility(for: .queue).isEnabled
            ) {
                model.presentPlaybackQueue()
            }
        }
    }

    private var hasPlaybackItem: Bool {
        model.hasCurrentPlaybackItem
    }

    private var primaryControlFill: Color {
        CadenceTheme.playerControl(
            hasPlaybackItem ? .active : .disabled
        )
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

    private func accessibility(
        for control: PlayerTransportControl
    ) -> PlayerBarAccessibilityControl {
        PlayerBarAccessibilityContract.control(
            control,
            hasPlaybackItem: hasPlaybackItem,
            isPlaying: model.isPlaying,
            repeatMode: model.repeatMode
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
                .foregroundStyle(
                    CadenceTheme.playerControl(
                        isEnabled ? (isActive ? .active : .normal) : .disabled
                    )
                )
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
        VStack(alignment: .leading, spacing: PlayerBarLayoutMetrics.metadataSpacing) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CadenceTheme.playerControl(.normal))
                .lineLimit(1)
            Text(artist)
                .font(.caption)
                .foregroundStyle(CadenceTheme.playerMetadata)
                .lineLimit(1)
        }
    }
}
