import Foundation

extension CadenceAppModel {
    var customArtistImages: [ArtistPreview.ID: ArtworkAsset] {
        _ = artworkRevision
        guard let artworkRepository = previewArtworkRepository else {
            return [:]
        }
        return Dictionary(
            uniqueKeysWithValues: artists.compactMap { artist in
                artworkRepository.asset(for: .artist(artist.id))
                    .map { (artist.id, $0) }
            }
        )
    }

    func customArtwork(for target: ArtworkTarget) -> ArtworkAsset? {
        _ = artworkRevision
        guard !target.isManaged,
              let artworkRepository = previewArtworkRepository else {
            return nil
        }
        return artworkRepository.asset(for: target)
    }

    func resolvedArtwork(for artist: ArtistPreview) -> ResolvedArtworkSource {
        ArtworkResolver.artist(
            custom: customArtwork(for: .artist(artist.id))
        )
    }

    func resolvedArtwork(for album: AlbumPreview) -> ResolvedArtworkSource {
        ArtworkResolver.album(
            custom: customArtwork(for: .album(album.id)),
            catalog: album.artworkPalette
        )
    }

    func resolvedArtwork(for track: TrackPreview) -> ResolvedArtworkSource {
        let album = albums.first { $0.id == track.albumID }
        return ArtworkResolver.track(
            custom: customArtwork(for: .track(track.id)),
            albumCustom: customArtwork(for: .album(track.albumID)),
            albumCatalog: album?.artworkPalette
        )
    }

    func hasCustomArtwork(for target: ArtworkTarget) -> Bool {
        if let managed = target.managedOwner {
            return managedArtworkID(
                kind: managed.kind,
                id: managed.id
            ) != nil
        }
        return customArtwork(for: target) != nil
    }

    func setCustomArtwork(
        data: Data,
        scale: CGFloat,
        normalizedOffset: CGSize,
        for target: ArtworkTarget
    ) {
        guard artworkTargetExists(target), !data.isEmpty else {
            return
        }
        if let managed = target.managedOwner {
            Task { @MainActor in
                do {
                    try await librarySession.store.setArtwork(
                        ManagedArtworkEditRequest(
                            ownerKind: managed.kind,
                            ownerID: managed.id,
                            data: data,
                            scale: scale,
                            normalizedOffset: normalizedOffset
                        ),
                        location: librarySession.location
                    )
                    artworkRevision += 1
                    if managed.kind == .smartCollection {
                        await loadPersistedSmartCollections()
                    }
                } catch {
                    artworkImportError = error.localizedDescription
                }
            }
            return
        }
        guard let artworkRepository = previewArtworkRepository else {
            return
        }
        let asset: ArtworkAsset = if let existing = artworkRepository.asset(for: target) {
            existing.replacingCrop(
                data: data,
                scale: scale,
                normalizedOffset: normalizedOffset
            )
        } else {
            ArtworkAsset(
                data: data,
                scale: scale,
                normalizedOffset: normalizedOffset
            )
        }
        artworkRepository.setAsset(asset, for: target)
        artworkRevision += 1
    }

    func removeCustomArtwork(for target: ArtworkTarget) {
        if let managed = target.managedOwner {
            Task { @MainActor in
                do {
                    try await librarySession.store.removeArtwork(
                        ownerKind: managed.kind,
                        ownerID: managed.id,
                        location: librarySession.location
                    )
                    artworkRevision += 1
                    if managed.kind == .smartCollection {
                        await loadPersistedSmartCollections()
                    }
                } catch {
                    artworkImportError = error.localizedDescription
                }
            }
            return
        }
        guard let artworkRepository = previewArtworkRepository,
              artworkRepository.asset(for: target) != nil else {
            return
        }
        artworkRepository.removeAsset(for: target)
        artworkRevision += 1
    }

    func requestArtworkImport(for target: ArtworkTarget) {
        guard artworkTargetExists(target) else {
            return
        }
        pendingArtworkImportTarget = target
        isArtworkImporterPresented = true
    }

    func prepareArtworkCrop(data: Data) {
        guard
            let target = pendingArtworkImportTarget,
            let descriptor = artworkDescriptor(for: target),
            !data.isEmpty
        else {
            cancelArtworkImport()
            return
        }
        artworkCropDraft = ArtworkCropDraft(
            target: target,
            title: descriptor.title,
            data: data,
            shape: descriptor.shape
        )
        pendingArtworkImportTarget = nil
        isArtworkImporterPresented = false
    }

    func finishArtworkCrop(
        _ draft: ArtworkCropDraft,
        scale: CGFloat,
        normalizedOffset: CGSize
    ) {
        setCustomArtwork(
            data: draft.data,
            scale: scale,
            normalizedOffset: normalizedOffset,
            for: draft.target
        )
        artworkCropDraft = nil
    }

    func cancelArtworkCrop() {
        artworkCropDraft = nil
    }

    func cancelArtworkImport() {
        pendingArtworkImportTarget = nil
        isArtworkImporterPresented = false
    }

    func presentArtworkImportError(_ message: String) {
        artworkImportError = message
        cancelArtworkImport()
    }

    func dismissArtworkImportError() {
        artworkImportError = nil
    }

    func setCustomImage(
        _ asset: ArtistImageAsset,
        for artist: ArtistPreview
    ) {
        guard artists.contains(where: { $0.id == artist.id }),
              let artworkRepository = previewArtworkRepository else {
            return
        }
        artworkRepository.setAsset(asset, for: .artist(artist.id))
        artworkRevision += 1
    }

    func removeCustomImage(for artist: ArtistPreview) {
        removeCustomArtwork(for: .artist(artist.id))
    }

    private func artworkTargetExists(_ target: ArtworkTarget) -> Bool {
        if let managed = target.managedOwner {
            return managedArtworkIDExists(
                kind: managed.kind,
                id: managed.id
            )
        }
        return switch target {
        case let .artist(id):
            artists.contains { $0.id == id }
        case let .album(id):
            albums.contains { $0.id == id }
        case let .track(id):
            tracks.contains { $0.id == id }
        case .managedArtist, .managedAlbum, .managedTrack,
             .managedPlaylist, .managedSmartCollection:
            false
        }
    }

    private var previewArtworkRepository: (any ArtworkRepository)? {
        runtimeEnvironment.previewFixture?.artworkRepository
    }

    private func artworkDescriptor(
        for target: ArtworkTarget
    ) -> (title: String, shape: ArtworkCropShape)? {
        if let managed = target.managedOwner {
            return managedArtworkDescriptor(
                kind: managed.kind,
                id: managed.id
            )
        }
        switch target {
        case let .artist(id):
            guard let artist = artists.first(where: { $0.id == id }) else {
                return nil
            }
            return (artist.name, .circle)
        case let .album(id):
            guard let album = albums.first(where: { $0.id == id }) else {
                return nil
            }
            return (album.title, .square)
        case let .track(id):
            guard let track = tracks.first(where: { $0.id == id }) else {
                return nil
            }
            return (track.title, .square)
        case .managedArtist, .managedAlbum, .managedTrack,
             .managedPlaylist, .managedSmartCollection:
            return nil
        }
    }

    private func managedArtworkDescriptor(
        kind: ArtworkOwnerKind,
        id: UUID
    ) -> (title: String, shape: ArtworkCropShape)? {
        switch kind {
        case .artist:
            guard let artist = librarySession.store.artists.first(
                where: { $0.id == id }
            ) else {
                return nil
            }
            return (artist.name, .circle)
        case .album:
            guard let album = librarySession.store.albums.first(
                where: { $0.id == id }
            ) else {
                return nil
            }
            return (album.title, .square)
        case .track:
            guard let track = librarySession.store.tracks.first(
                where: { $0.id == id }
            ) else {
                return nil
            }
            return (track.title, .square)
        case .playlist:
            guard let playlist = librarySession.store.playlists.first(
                where: { $0.id == id }
            ) else {
                return nil
            }
            return (playlist.name, .square)
        case .smartCollection:
            guard let collection = smartCollections.first(
                where: { $0.id == id }
            ) else {
                return nil
            }
            return (collection.name, .square)
        }
    }

    private func managedArtworkIDExists(
        kind: ArtworkOwnerKind,
        id: UUID
    ) -> Bool {
        switch kind {
        case .artist:
            librarySession.store.artists.contains { $0.id == id }
        case .album:
            librarySession.store.albums.contains { $0.id == id }
        case .track:
            librarySession.store.tracks.contains { $0.id == id }
        case .playlist:
            librarySession.store.playlists.contains { $0.id == id }
        case .smartCollection:
            smartCollections.contains { $0.id == id }
        }
    }

    private func managedArtworkID(
        kind: ArtworkOwnerKind,
        id: UUID
    ) -> UUID? {
        switch kind {
        case .artist:
            librarySession.store.artists.first { $0.id == id }?
                .customArtworkID
        case .album:
            librarySession.store.albums.first { $0.id == id }?
                .customArtworkID
        case .track:
            librarySession.store.tracks.first { $0.id == id }?
                .customArtworkID
        case .playlist:
            librarySession.store.playlists.first { $0.id == id }?
                .customArtworkID
        case .smartCollection:
            smartCollections.first { $0.id == id }?.customArtworkID
        }
    }
}

private extension ArtworkTarget {
    var isManaged: Bool {
        managedOwner != nil
    }

    var managedOwner: (kind: ArtworkOwnerKind, id: UUID)? {
        switch self {
        case let .managedArtist(id):
            (.artist, id)
        case let .managedAlbum(id):
            (.album, id)
        case let .managedTrack(id):
            (.track, id)
        case let .managedPlaylist(id):
            (.playlist, id)
        case let .managedSmartCollection(id):
            (.smartCollection, id)
        case .artist, .album, .track:
            nil
        }
    }
}
