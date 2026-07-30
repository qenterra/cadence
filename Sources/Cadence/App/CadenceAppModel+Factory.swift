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
        tracks: [TrackPreview] = .mockLibrary,
        tags: [TagPreview] = .mockTags,
        tagAssignments: Set<TagAssignmentPreview> = .mockTagAssignments,
        tagExclusions: Set<TagExclusionPreview> = .mockTagExclusions,
        smartCollections: [SmartCollectionPreview] = .mockSmartCollections,
        lyricDocuments: [TrackPreview.ID: LyricDocument] = .mockLyrics,
        favoriteAlbumDates: [AlbumPreview.ID: Date] = .mockAlbumFavorites,
        favoriteArtistDates: [ArtistPreview.ID: Date] = .mockArtistFavorites,
        importCandidates: [ImportCandidatePreview] = .mockImportCandidates,
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
