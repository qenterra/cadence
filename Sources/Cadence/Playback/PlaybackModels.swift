import Foundation

enum PlaybackBackendKind: String, Sendable {
    case native
    case pcm
}

enum PlaybackTransportState: Equatable, Sendable {
    case idle
    case loading
    case paused
    case playing
    case failed
}

enum PlaybackQueueSource: Hashable, Sendable {
    case album(UUID)
    case artist(UUID)
    case smartCollection(UUID)
    case playlist(UUID)
    case favorites
    case allTracks
    case externalFiles
    case adHoc
}

enum AudioTransportKind: String, Sendable {
    case airPlay
    case bluetooth
    case builtIn
    case unknown
    case wired
}

struct AudioRouteSnapshot: Equatable, Sendable {
    let name: String
    let transport: AudioTransportKind

    static let unknown = AudioRouteSnapshot(
        name: "System Output",
        transport: .unknown
    )
}

struct AudioPathSnapshot: Equatable, Sendable {
    let codec: String
    let container: String
    let sourceBitDepth: Int?
    let sourceSampleRate: Double
    let sourceChannelCount: Int
    let sourceSpatialFormat: StoredSpatialFormat
    let backend: PlaybackBackendKind
    let rendererSampleRate: Double?
    let rendererChannelCount: Int?
    let outputRoute: AudioRouteSnapshot
    let nextTransitionIsGapless: Bool
}

struct PlaybackFailure: Equatable, Error, LocalizedError, Sendable {
    enum Kind: Equatable, Sendable {
        case general
        case silentStart
    }

    let trackID: UUID?
    let message: String
    let kind: Kind

    init(
        trackID: UUID?,
        message: String,
        kind: Kind = .general
    ) {
        self.trackID = trackID
        self.message = message
        self.kind = kind
    }

    static func silentStart(
        trackID: UUID
    ) -> PlaybackFailure {
        PlaybackFailure(
            trackID: trackID,
            message: "Playback did not reach the audio output. Try again.",
            kind: .silentStart
        )
    }

    var errorDescription: String? {
        message
    }
}

struct ResolvedPlaybackTrack: Hashable, Sendable {
    let track: PlaybackTrack
    let mediaURL: URL
}

extension PlaybackTrack {
    func replacingArtworkID(_ artworkID: UUID?) -> PlaybackTrack {
        PlaybackTrack(
            id: id,
            title: title,
            artistID: artistID,
            artist: artist,
            albumID: albumID,
            album: album,
            duration: duration,
            codec: codec,
            container: container,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitrate: bitrate,
            bitDepth: bitDepth,
            spatialFormat: spatialFormat,
            relativeMediaPath: relativeMediaPath,
            lyricRelativePath: lyricRelativePath,
            artworkID: artworkID,
            replayGainTrackGain: replayGainTrackGain,
            replayGainTrackPeak: replayGainTrackPeak,
            year: year,
            discNumber: discNumber,
            trackNumber: trackNumber
        )
    }
}

struct PlaybackCoordinatorState: Equatable, Sendable {
    var transport: PlaybackTransportState = .idle
    var queue: PlaybackQueueState?
    var currentTrack: PlaybackTrack?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var activeBackend: PlaybackBackendKind?
    var isBuffering = false
    var failure: PlaybackFailure?
    var audioPath: AudioPathSnapshot?

    var isPlaying: Bool {
        transport == .playing
    }
}

struct PlaybackIndicatorState: Equatable, Sendable {
    let currentTrackID: UUID?
    let isPlaying: Bool

    static let idle = PlaybackIndicatorState(
        currentTrackID: nil,
        isPlaying: false
    )
}
