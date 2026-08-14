import Foundation

private struct ImportRuntime {
    let destination: ManagedLibraryImportDestination?
    let coordinator: ImportCoordinator?
    let availability: ImportRuntimeAvailability
}

private struct RemoteRuntime {
    let source: RemotePlaybackSource
    let controller: RemoteLibraryController
}

extension CadenceAppModel {
    static func production(
        librarySession: LibrarySession
    ) -> CadenceAppModel {
        let importRuntime = importRuntime(librarySession: librarySession)
        let remote = remoteRuntime(librarySession: librarySession)
        let externalAudioSession = ExternalAudioSession()
        let playbackCoordinator = PlaybackCoordinator(
            resolver: CompositePlaybackTrackResolver(
                external: externalAudioSession,
                managed: ManagedPlaybackTrackResolver(
                    librarySession: librarySession,
                    remoteSource: remote.source
                )
            ),
            backends: [
                PCMPlaybackBackend(),
                NativePlaybackBackend(),
            ],
            systemMediaSession: SystemMediaSession(),
            audioRouteProvider: SystemAudioRouteProvider()
        )
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: importRuntime.availability,
            librarySession: librarySession,
            importCoordinator: importRuntime.coordinator,
            importDestination: importRuntime.destination,
            importRecovery: importRuntime.destination.map {
                ManagedLibraryImportRecovery(destination: $0)
            },
            playbackCoordinator: playbackCoordinator,
            externalAudioSession: externalAudioSession,
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

    static func remoteRuntime(
        librarySession: LibrarySession
    ) -> RemoteRuntime {
        let source = RemotePlaybackSource()
        let identityExpectation: RemoteLibraryIdentityExpectation
        switch librarySession.availability {
        case .empty:
            identityExpectation = .unbound
        case .recovering, .ready:
            do {
                guard let location = librarySession.location else {
                    identityExpectation = .unavailable(
                        "Remote libraries are unavailable because the local library location is missing."
                    )
                    break
                }
                let identity = try ManagedLibraryPackage(
                    location: location
                ).readIdentity()
                identityExpectation = .exact(identity.id)
            } catch {
                identityExpectation = .unavailable(
                    "Remote libraries are unavailable because the local library identity cannot be read."
                )
            }
        case let .failed(failure):
            identityExpectation = .unavailable(failure.message)
        case .preview:
            identityExpectation = .unavailable(
                "Remote libraries are unavailable until the local library is ready."
            )
        }
        return RemoteRuntime(
            source: source,
            controller: RemoteLibraryController(
                source: source,
                identityExpectation: identityExpectation
            )
        )
    }
}
