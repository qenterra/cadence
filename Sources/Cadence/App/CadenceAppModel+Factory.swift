import Foundation

extension CadenceAppModel {
    static func production(
        librarySession: LibrarySession
    ) -> CadenceAppModel {
        let importRuntime = importRuntime(librarySession: librarySession)
        let remote = remoteRuntime(librarySession: librarySession)
        let playbackCoordinator = PlaybackCoordinator(
            resolver: ManagedPlaybackTrackResolver(
                librarySession: librarySession,
                remoteSource: remote.source
            ),
            backends: [
                PCMPlaybackBackend(),
                NativePlaybackBackend(),
            ],
            systemMediaSession: SystemMediaSession(),
            audioRouteProvider: SystemAudioRouteProvider(),
            qualityProfileStore: UserDefaultsAudioQualityProfileStore()
        )
        let model = CadenceAppModel(
            librarySession: librarySession,
            tracks: [],
            tags: [],
            tagAssignments: [],
            tagExclusions: [],
            smartCollections: [],
            lyricDocuments: [:],
            favoriteAlbumDates: [:],
            favoriteArtistDates: [:],
            importCandidates: [],
            importCoordinator: importRuntime.coordinator,
            importDestination: importRuntime.destination,
            importRecovery: importRuntime.destination.map {
                ManagedLibraryImportRecovery(destination: $0)
            },
            playbackCoordinator: playbackCoordinator,
            remoteLibraryController: remote.controller
        )
        Task {
            await remote.controller.restore()
        }
        return model
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
            librarySession: .preview(),
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
    }
}

private extension CadenceAppModel {
    static func importRuntime(
        librarySession: LibrarySession
    ) -> (
        destination: ManagedLibraryImportDestination?,
        coordinator: ImportCoordinator
    ) {
        let destination = librarySession.location.map {
            ManagedLibraryImportDestination(
                package: ManagedLibraryPackage(location: $0),
                repository: librarySession.store.repository
            )
        }
        let duplicateLookup = destination.map { destination in
            ImportDuplicateLookup { probes in
                try await destination.duplicateEvidence(probes: probes)
            }
        } ?? .empty
        return (
            destination,
            ImportCoordinator(
                service: ImportInspectionService(
                    duplicateLookup: duplicateLookup
                ),
                importer: destination.map {
                    ManagedLibraryImporter(destination: $0)
                }
            )
        )
    }

    static func remoteRuntime(
        librarySession: LibrarySession
    ) -> (
        source: RemotePlaybackSource,
        controller: RemoteLibraryController
    ) {
        let source = RemotePlaybackSource()
        let expectedLibraryID = librarySession.location.flatMap {
            try? ManagedLibraryPackage(location: $0).readIdentity().id
        }
        return (
            source,
            RemoteLibraryController(
                source: source,
                expectedLibraryID: expectedLibraryID
            )
        )
    }
}
