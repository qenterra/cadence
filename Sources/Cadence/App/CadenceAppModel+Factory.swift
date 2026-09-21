import Foundation

private struct ImportRuntime {
    let destination: ManagedLibraryImportDestination?
    let coordinator: ImportCoordinator?
    let availability: ImportRuntimeAvailability
}

extension CadenceAppModel {
    static func production(
        librarySession: LibrarySession,
        notificationController: CadenceNotificationController? = nil
    ) -> CadenceAppModel {
        let importRuntime = importRuntime(librarySession: librarySession)
        let externalAudioSession = ExternalAudioSession()
        let systemMediaArtworkProvider = SystemMediaArtworkProvider { id in
            if let asset = externalAudioSession.artwork(id: id) {
                return asset
            }
            return await librarySession.store.artworkAsset(
                id: id,
                location: librarySession.location,
                variant: .original
            )
        }
        let playbackCoordinator = PlaybackCoordinator(
            resolver: CompositePlaybackTrackResolver(
                external: externalAudioSession,
                managed: ManagedPlaybackTrackResolver(
                    librarySession: librarySession
                )
            ),
            backends: productionPlaybackBackends(),
            systemMediaSession: SystemMediaSession(
                artworkProvider: systemMediaArtworkProvider
            ),
            audioRouteProvider: SystemAudioRouteProvider(),
            notificationController: notificationController
        )
        return CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: importRuntime.availability,
            librarySession: librarySession,
            importCoordinator: importRuntime.coordinator,
            importDestination: importRuntime.destination,
            importRecovery: importRuntime.destination.map {
                ManagedLibraryImportRecovery(destination: $0)
            },
            playbackCoordinator: playbackCoordinator,
            externalAudioSession: externalAudioSession
        )
    }

    static func preview(
        tracks: [TrackPreview] = [],
        tags: [TagPreview] = [],
        tagAssignments: Set<TagAssignmentPreview> = [],
        tagExclusions: Set<TagExclusionPreview> = [],
        smartCollections: [SmartCollectionPreview] = [],
        lyricDocuments: [TrackPreview.ID: LyricDocument] = [:],
        favoriteAlbumDates: [AlbumPreview.ID: Date] = [:],
        favoriteArtistDates: [ArtistPreview.ID: Date] = [:],
        importCandidates: [ImportCandidatePreview] = [],
        artworkRepository: any ArtworkRepository = InMemoryArtworkRepository()
    ) -> CadenceAppModel {
        CadenceAppModel(
            runtimeEnvironment: .preview(
                CadencePreviewFixture(
                    tracks: tracks,
                    tags: tags,
                    tagAssignments: tagAssignments,
                    tagExclusions: tagExclusions,
                    smartCollections: smartCollections,
                    lyricDocuments: lyricDocuments,
                    favoriteAlbumDates: favoriteAlbumDates,
                    favoriteArtistDates: favoriteArtistDates,
                    importCandidates: importCandidates,
                    artworkRepository: artworkRepository
                )
            ),
            importRuntimeAvailability: .preview,
            librarySession: .preview()
        )
    }
}

private extension CadenceAppModel {
    static func productionPlaybackBackends() -> [any PlaybackBackend] {
        [
            CrossfadePlaybackBackend(
                kind: .pcm,
                primary: PCMPlaybackBackend(),
                secondary: PCMPlaybackBackend()
            ),
            CrossfadePlaybackBackend(
                kind: .native,
                primary: NativePlaybackBackend(),
                secondary: NativePlaybackBackend()
            ),
        ]
    }

    static func importRuntime(
        librarySession: LibrarySession
    ) -> ImportRuntime {
        if case let .failed(failure) = librarySession.availability {
            let destination = librarySession.location.map {
                ManagedLibraryImportDestination(
                    package: ManagedLibraryPackage(location: $0),
                    repository: librarySession.store.repository
                )
            }
            return ImportRuntime(
                destination: destination,
                coordinator: nil,
                availability: .unavailable(failure.message)
            )
        }
        guard let location = librarySession.location else {
            return ImportRuntime(
                destination: nil,
                coordinator: nil,
                availability: .unavailable(
                    "Import is unavailable because the library location could not be resolved."
                )
            )
        }
        let destination = ManagedLibraryImportDestination(
            package: ManagedLibraryPackage(location: location),
            repository: librarySession.store.repository
        )
        let duplicateLookup = ImportDuplicateLookup { probes in
            try await destination.duplicateEvidence(probes: probes)
        }
        return ImportRuntime(
            destination: destination,
            coordinator: ImportCoordinator(
                service: ImportInspectionService(
                    duplicateLookup: duplicateLookup
                ),
                importer: ManagedLibraryImporter(destination: destination)
            ),
            availability: .available
        )
    }
}
