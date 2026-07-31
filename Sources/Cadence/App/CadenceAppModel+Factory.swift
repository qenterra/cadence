import Foundation

extension CadenceAppModel {
    static func production(
        librarySession: LibrarySession
    ) -> CadenceAppModel {
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
        let importer = destination.map {
            ManagedLibraryImporter(destination: $0)
        }
        let coordinator = ImportCoordinator(
            service: ImportInspectionService(
                duplicateLookup: duplicateLookup
            ),
            importer: importer
        )
        let playbackCoordinator = PlaybackCoordinator(
            resolver: ManagedPlaybackTrackResolver(
                librarySession: librarySession
            ),
            backends: [
                PCMPlaybackBackend(),
                NativePlaybackBackend(),
            ],
            systemMediaSession: SystemMediaSession(),
            audioRouteProvider: SystemAudioRouteProvider(),
            qualityProfileStore: UserDefaultsAudioQualityProfileStore()
        )
        return CadenceAppModel(
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
            importCoordinator: coordinator,
            importDestination: destination,
            importRecovery: destination.map {
                ManagedLibraryImportRecovery(destination: $0)
            },
            playbackCoordinator: playbackCoordinator
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
