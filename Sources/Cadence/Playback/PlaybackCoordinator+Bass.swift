import Foundation

extension PlaybackCoordinator {
    func beginBassEnvelopeAnalysis(
        for resolved: ResolvedPlaybackTrack,
        generation: Int
    ) {
        bassEnvelopeWorker?.cancel()
        bassEnvelopeWorker = nil
        bassEnvelope = nil
        bassEnvelopeTrackID = resolved.track.id

        let trackID = resolved.track.id
        let url = resolved.mediaURL
        let worker = Task.detached(priority: .utility) {
            try? PlaybackBassEnvelopeAnalyzer.analyze(url: url)
        }
        bassEnvelopeWorker = worker

        Task { @MainActor [weak self] in
            let envelope = await worker.value
            guard let self,
                  !worker.isCancelled,
                  generation == loadGeneration,
                  state.currentTrack?.id == trackID
            else {
                return
            }
            bassEnvelope = envelope
        }
    }

    func cancelBassEnvelopeAnalysis() {
        bassEnvelopeWorker?.cancel()
        bassEnvelopeWorker = nil
        bassEnvelope = nil
        bassEnvelopeTrackID = nil
    }
}
