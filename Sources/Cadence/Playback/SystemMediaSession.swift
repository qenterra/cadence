import Foundation
import MediaPlayer

@MainActor
final class SystemMediaSession: SystemMediaSessionControlling {
    private let commandCenter: MPRemoteCommandCenter
    private let nowPlayingInfoCenter: MPNowPlayingInfoCenter
    private var handler: ((SystemMediaCommand) -> Void)?
    private var registrations: [(MPRemoteCommand, Any)] = []
    private var lastTrackID: UUID?
    private var lastTransport: PlaybackTransportState?
    private var lastQueue: PlaybackQueueState?
    private var lastElapsedTime: TimeInterval = 0
    private var lastUpdateUptime: TimeInterval = 0

    init(
        commandCenter: MPRemoteCommandCenter = .shared(),
        nowPlayingInfoCenter: MPNowPlayingInfoCenter = .default()
    ) {
        self.commandCenter = commandCenter
        self.nowPlayingInfoCenter = nowPlayingInfoCenter
    }

    func activate(
        handler: @escaping (SystemMediaCommand) -> Void
    ) {
        self.handler = handler
        guard registrations.isEmpty else {
            return
        }

        register(commandCenter.playCommand) { .play }
        register(commandCenter.pauseCommand) { .pause }
        register(commandCenter.togglePlayPauseCommand) { .toggle }
        register(commandCenter.nextTrackCommand) { .next }
        register(commandCenter.previousTrackCommand) { .previous }

        let positionToken = commandCenter.changePlaybackPositionCommand
            .addTarget { [weak self] event in
                guard
                    let event = event as? MPChangePlaybackPositionCommandEvent
                else {
                    return .commandFailed
                }
                Task { @MainActor [weak self] in
                    self?.handler?(.changePosition(event.positionTime))
                }
                return .success
            }
        registrations.append((
            commandCenter.changePlaybackPositionCommand,
            positionToken
        ))

        commandCenter.skipForwardCommand.preferredIntervals = [15]
        register(commandCenter.skipForwardCommand) { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval
                ?? 15
            return .skipForward(interval)
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        register(commandCenter.skipBackwardCommand) { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval
                ?? 15
            return .skipBackward(interval)
        }
    }

    func update(
        state: PlaybackCoordinatorState
    ) {
        guard let track = state.currentTrack else {
            clear()
            return
        }
        let uptime = ProcessInfo.processInfo.systemUptime
        let requiresImmediateUpdate = track.id != lastTrackID
            || state.transport != lastTransport
            || state.queue != lastQueue
            || abs(state.currentTime - lastElapsedTime) > 2
        guard
            requiresImmediateUpdate
            || uptime - lastUpdateUptime >= 1
        else {
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: state.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1 : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let queue = state.queue {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = queue.currentIndex
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] =
                queue.orderedTrackIDs.count
        }
        nowPlayingInfoCenter.nowPlayingInfo = info
        nowPlayingInfoCenter.playbackState = state.isPlaying
            ? .playing
            : .paused
        lastTrackID = track.id
        lastTransport = state.transport
        lastQueue = state.queue
        lastElapsedTime = state.currentTime
        lastUpdateUptime = uptime
    }

    func clear() {
        nowPlayingInfoCenter.nowPlayingInfo = nil
        nowPlayingInfoCenter.playbackState = .stopped
        lastTrackID = nil
        lastTransport = nil
        lastQueue = nil
        lastElapsedTime = 0
        lastUpdateUptime = 0
    }

    func shutdown() {
        for (command, token) in registrations {
            command.removeTarget(token)
        }
        registrations.removeAll()
        handler = nil
        clear()
    }

    private func register(
        _ command: MPRemoteCommand,
        mapping: @escaping () -> SystemMediaCommand
    ) {
        register(command) { _ in mapping() }
    }

    private func register(
        _ command: MPRemoteCommand,
        mapping: @escaping (MPRemoteCommandEvent) -> SystemMediaCommand
    ) {
        let token = command.addTarget { [weak self] event in
            let mapped = mapping(event)
            Task { @MainActor [weak self] in
                self?.handler?(mapped)
            }
            return .success
        }
        registrations.append((command, token))
    }
}
