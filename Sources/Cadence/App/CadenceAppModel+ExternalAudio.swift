import Foundation

extension CadenceAppModel {
    var isCurrentPlaybackExternal: Bool {
        playbackCoordinator?.state.queue?.source == .externalFiles
    }

    var currentExternalAudioItem: ExternalAudioItem? {
        guard isCurrentPlaybackExternal,
              let trackID = playbackCoordinator?.state.currentTrack?.id
        else {
            return nil
        }
        return externalAudioSession?.item(id: trackID)
    }

    func openExternalAudio(urls: [URL]) async {
        guard let externalAudioSession, let playbackCoordinator else {
            return
        }

        let result = await externalAudioSession.prepare(urls: urls)
        guard !result.items.isEmpty else {
            externalAudioOpenError = result.failures.first
                ?? "Cadence could not open the selected audio file."
            return
        }

        externalAudioSession.replace(with: result.items)
        externalAudioOpenError = nil
        externalAudioNotice = result.skippedCount > 0
            ? "Some files could not be opened."
            : nil

        let trackIDs = result.items.map(\.id)
        let didStart = await playbackCoordinator.startQueue(
            source: .externalFiles,
            trackIDs: trackIDs,
            startingAt: trackIDs[0]
        )
        if !didStart {
            externalAudioSession.end()
            externalAudioOpenError = "Cadence could not start playback."
        }
    }

    func endExternalAudioSession() {
        externalAudioSession?.end()
        externalAudioNotice = nil
        externalAudioOpenError = nil
    }

    func addCurrentExternalAudioToLibrary() {
        guard let url = currentExternalAudioItem?.sourceURL else {
            return
        }
        requestNavigationDestination(.importMusic)
        startImportScan(source: ImportSource(urls: [url]))
    }

    func playbackArtworkAsset(
        id: UUID,
        variant: ArtworkAssetVariant = .original
    ) async -> ArtworkAsset? {
        if let asset = externalAudioSession?.artwork(id: id) {
            return asset
        }
        return await librarySession.store.artworkAsset(
            id: id,
            location: librarySession.location,
            variant: variant
        )
    }
}
