import QenTerraMediaComponents
import SwiftUI

struct PlayerBar: View {
    @Environment(\.visualRegressionUsesStableSystemControls)
    var usesStableSystemControls
    @Bindable var model: CadenceAppModel
    let suspendsProgressAnimation: Bool
    @AppStorage(CadencePreferences.Keys.playbackTimeDisplay)
    private var timeDisplayRaw = PlaybackTimeDisplayMode.elapsed.rawValue
    @State private var pendingSeek = CadencePendingSeekState()

    var body: some View {
        Group {
            if suspendsProgressAnimation {
                sharedPlayerBar
            } else {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    sharedPlayerBar
                }
            }
        }
        .onChange(of: model.currentPlaybackTrack?.id, initial: true) { _, itemID in
            pendingSeek.updateCurrentItem(itemID)
        }
    }
}

private extension PlayerBar {
    var adapterPresentation: CadencePlayerBarAdapterPresentation {
        CadencePlayerAdapters.playerBar(
            from: CadencePlayerBarSnapshot(
                item: model.currentPlaybackTrack.map {
                    CadencePlayerItemSnapshot(
                        id: $0.id,
                        title: $0.title,
                        artist: $0.artist,
                        isExternal: model.isCurrentPlaybackExternal
                    )
                },
                isPlaying: model.isPlaying,
                isShuffleEnabled: model.isShuffleEnabled,
                repeatMode: model.repeatMode,
                presentationTime: model.playbackPresentationTime(),
                duration: model.playbackDuration,
                volume: model.volume,
                isMuted: model.volume <= 0,
                isQueuePresented: isQueuePresented,
                timeDisplayMode: PlaybackTimeDisplayMode(rawValue: timeDisplayRaw) ?? .elapsed,
                libraryTrackCount: model.librarySession.store.catalogCounts.liveTrackCount
            ),
            pendingSeekProgress: pendingSeek.progress
        )
    }

    var sharedPlayerBar: some View {
        let adapter = adapterPresentation
        return QenTerraMediaComponents.PlayerBar(
            presentation: adapter.presentation,
            actions: playerActions,
            artwork: {
                if let track = model.currentPlaybackTrack {
                    ProductionArtworkView(
                        model: model,
                        artworkID: track.artworkID,
                        title: track.title,
                        placeholder: .track,
                        cornerRadius: CadenceTheme.radiusControl
                    )
                } else {
                    Color.clear
                }
            },
            metadataAccessory: {
                if adapter.showsExternalImportAction,
                   let track = model.currentPlaybackTrack {
                    Button(
                        "Add to Library…",
                        systemImage: "plus.rectangle.on.folder"
                    ) {
                        model.addCurrentExternalAudioToLibrary()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(CadenceRowButtonStyle())
                    .help("Add to Library…")
                    .accessibilityLabel("Add \(track.title) to Library")
                }
            },
            favoriteAccessory: {
                if adapter.showsFavoriteAccessory {
                    PlayerBarFavoriteControl(model: model)
                }
            },
            statusAccessory: {
                playbackFailureMenu
            },
            routeAccessory: {
                audioOutputMenu
            }
        )
    }

    var playerActions: PlayerBarActions {
        PlayerBarActions(
            showNowPlaying: {
                model.presentNowPlaying(panel: .lyrics)
            },
            togglePlayback: {
                model.togglePlayback()
            },
            previous: {
                model.selectPreviousTrack()
            },
            next: {
                model.selectNextTrack()
            },
            seek: { progress in
                beginSeek(to: progress)
            },
            setVolume: { volume in
                model.volume = volume
            },
            toggleMute: {
                model.toggleMute()
            },
            showQueue: {
                model.presentPlaybackQueue()
            },
            toggleShuffle: {
                model.isShuffleEnabled.toggle()
            },
            cycleRepeatMode: {
                model.cycleRepeatMode()
            }
        )
    }

    var isQueuePresented: Bool {
        model.playbackWorkspace == .nowPlaying
            && model.selectedNowPlayingPanel == .queue
    }

    func beginSeek(to progress: Double) {
        guard let itemID = model.currentPlaybackTrack?.id else { return }
        let token = pendingSeek.begin(progress: progress, itemID: itemID)
        Task { @MainActor in
            await model.seekPlayback(toProgress: progress)
            pendingSeek.complete(token)
        }
    }
}
