import Foundation

typealias PlaybackBassEnvelopeLoading =
    @Sendable (URL) async -> PlaybackBassEnvelope?

let defaultPlaybackBassEnvelopeLoader: PlaybackBassEnvelopeLoading = { url in
    guard !Task.isCancelled else {
        return nil
    }
    return try? PlaybackBassEnvelopeAnalyzer.analyze(url: url)
}

struct PlaybackBassMediaIdentity: Hashable, Sendable {
    let trackID: UUID
    let mediaURL: URL

    init(resolved: ResolvedPlaybackTrack) {
        trackID = resolved.track.id
        mediaURL = resolved.mediaURL.standardizedFileURL
    }
}

struct PlaybackBassEnvelopeCache {
    private let capacity: Int
    private var envelopes: [PlaybackBassMediaIdentity: PlaybackBassEnvelope]
        = [:]
    private var recency: [PlaybackBassMediaIdentity] = []

    init(capacity: Int) {
        self.capacity = max(capacity, 0)
    }

    var count: Int {
        envelopes.count
    }

    mutating func value(
        for identity: PlaybackBassMediaIdentity
    ) -> PlaybackBassEnvelope? {
        guard let envelope = envelopes[identity] else {
            return nil
        }
        markMostRecent(identity)
        return envelope
    }

    mutating func insert(
        _ envelope: PlaybackBassEnvelope,
        for identity: PlaybackBassMediaIdentity
    ) {
        guard capacity > 0 else {
            return
        }
        envelopes[identity] = envelope
        markMostRecent(identity)
        while envelopes.count > capacity, let leastRecent = recency.first {
            recency.removeFirst()
            envelopes[leastRecent] = nil
        }
    }

    private mutating func markMostRecent(
        _ identity: PlaybackBassMediaIdentity
    ) {
        recency.removeAll { $0 == identity }
        recency.append(identity)
    }
}

extension PlaybackCoordinator {
    func invalidateBassState(resetBackend: Bool = true) {
        bassPresentationIsActive = false
        bassGeneration &+= 1
        bassEnvelopeWorker?.cancel()
        bassEnvelopeWorker = nil
        bassEnvelope = nil
        bassEnvelopeTrackID = nil
        if resetBackend {
            activeBackend?.resetBassAnalysis()
        }
    }

    func activateBassSource(
        for resolved: ResolvedPlaybackTrack,
        backend: any PlaybackBackend
    ) {
        invalidateBassState()
        guard state.transport == .playing,
              state.currentTrack?.id == resolved.track.id,
              state.activeBackend == backend.kind else {
            return
        }
        bassPresentationIsActive = true
        guard backend.bassLevelProvider == nil else {
            return
        }

        let mediaIdentity = PlaybackBassMediaIdentity(resolved: resolved)
        if let cachedEnvelope = bassEnvelopeCache.value(for: mediaIdentity) {
            bassEnvelope = cachedEnvelope
            bassEnvelopeTrackID = resolved.track.id
            return
        }

        let generation = bassGeneration
        let trackID = resolved.track.id
        let backendKind = backend.kind
        let intendedTransport = state.transport
        let loader = bassEnvelopeLoader
        let url = resolved.mediaURL
        let worker = Task.detached(priority: .utility) {
            await loader(url)
        }
        bassEnvelopeWorker = worker

        Task { @MainActor [weak self] in
            let envelope = await worker.value
            guard let self,
                  !worker.isCancelled,
                  generation == bassGeneration,
                  state.currentTrack?.id == trackID,
                  state.activeBackend == backendKind,
                  state.transport == intendedTransport,
                  intendedTransport == .playing else {
                return
            }
            if let envelope {
                bassEnvelopeCache.insert(envelope, for: mediaIdentity)
            }
            bassEnvelope = envelope
            bassEnvelopeTrackID = envelope == nil ? nil : trackID
            bassEnvelopeWorker = nil
        }
    }

    func activateBassSourceForCurrentTrack() {
        guard state.transport == .playing,
              let trackID = state.currentTrack?.id,
              let resolved = resolvedTracks[trackID],
              let activeBackend else {
            invalidateBassState()
            return
        }
        activateBassSource(for: resolved, backend: activeBackend)
    }

    func currentBassLevel() -> Float {
        guard state.transport == .playing,
              bassPresentationIsActive else {
            return 0
        }
        if let provider = activeBackend?.bassLevelProvider {
            let level = provider.currentBassLevel()
            return level.isFinite ? min(max(level, 0), 1) : 0
        }
        guard bassEnvelopeTrackID == state.currentTrack?.id else {
            return 0
        }
        return bassEnvelope?.level(at: presentationTime()) ?? 0
    }
}
