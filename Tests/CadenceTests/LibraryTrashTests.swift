@testable import Cadence
import Foundation
import SwiftData
import Testing

struct LibraryTrashTests {
    @Test("Version two Trash manifests remain readable after credit migration")
    func readsVersionTwoManifest() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Trash-V2-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let location = ManagedLibraryLocation(musicDirectory: root)
        try ManagedLibraryPackage(location: location)
            .bootstrapForConfirmedImport()
        let operationID = UUID()
        let manifest = ManagedTrashManifest(
            version: 2,
            operationID: operationID,
            targetKind: .track,
            createdAt: .now,
            artists: [],
            albums: [],
            tracks: [],
            artistCredits: nil,
            lyrics: [],
            artworks: [],
            tagAssignments: [],
            tagExclusions: [],
            playlistEntries: nil,
            originalRelativePaths: []
        )
        let store = ManagedTrashManifestStore(location: location)
        try store.write(manifest)

        #expect(try store.read(operationID: operationID).version == 2)
    }

    @Test("Deleting one credited artist keeps the shared track and restores the credit")
    func trashSharedPrimaryArtist() async throws {
        let fixture = try SharedArtistTrashFixture()
        defer { fixture.remove() }
        let repository = LibraryRepository(modelContainer: fixture.container)

        let operationID = try await repository.trash(
            targetKind: .artist,
            targetID: fixture.primaryArtistID,
            location: fixture.location
        )

        let context = ModelContext(fixture.container)
        #expect(fixture.mediaURL.fileExists)
        #expect(try context.fetch(FetchDescriptor<TrackRecord>()).count == 1)
        #expect(
            try context.fetch(FetchDescriptor<ArtistRecord>()).map(\.name)
                == ["темный принц"]
        )
        let remainingArtist = try #require(
            try context.fetch(FetchDescriptor<ArtistRecord>()).first
        )
        #expect(
            try context.fetch(FetchDescriptor<TrackArtistCreditRecord>())
                .map(\.artistID) == [remainingArtist.id]
        )
        #expect(
            try context.fetch(FetchDescriptor<TrackRecord>()).first?.artist?.name
                == "темный принц"
        )
        #expect(
            try context.fetch(FetchDescriptor<AlbumRecord>()).first?.artist?.name
                == "темный принц"
        )

        try await repository.restoreTrash(
            operationID: operationID,
            location: fixture.location
        )

        let restoredArtists = try context.fetch(FetchDescriptor<ArtistRecord>())
        let restoredCredits = try context.fetch(
            FetchDescriptor<TrackArtistCreditRecord>(
                sortBy: [SortDescriptor(\.position)]
            )
        )
        let restoredArtistNamesByID = Dictionary(
            uniqueKeysWithValues: restoredArtists.map { ($0.id, $0.name) }
        )
        #expect(Set(restoredArtists.map(\.name)) == ["madkid", "темный принц"])
        #expect(restoredCredits.map { restoredArtistNamesByID[$0.artistID] } == ["madkid", "темный принц"])
        #expect(
            try context.fetch(FetchDescriptor<TrackRecord>()).first?.artist?.name
                == "madkid"
        )
        #expect(
            try context.fetch(FetchDescriptor<AlbumRecord>()).first?.artist?.name
                == "madkid"
        )
        #expect(fixture.mediaURL.fileExists)
    }

    @Test("A captured confirmation still deletes after the dialog binding clears pending state")
    @MainActor
    func capturedDeletionConfirmation() async throws {
        let fixture = try DeletionHandoffFixture()
        defer { fixture.remove() }
        await fixture.session.store.loadInitialLibrary()
        let model = CadenceAppModel(
            librarySession: fixture.session,
            tracks: [],
            tags: [],
            tagAssignments: [],
            tagExclusions: [],
            smartCollections: [],
            lyricDocuments: [:],
            favoriteAlbumDates: [:],
            favoriteArtistDates: [:],
            importCandidates: []
        )
        model.requestLibraryDeletion(
            kind: .album,
            id: fixture.albumID,
            title: "Captured Album"
        )
        let captured = try #require(model.pendingLibraryDeletion)

        model.cancelLibraryDeletion()
        await model.confirmLibraryDeletion(captured)

        #expect(model.pendingLibraryDeletion == nil)
        #expect(fixture.session.store.albums.isEmpty)
        #expect(fixture.session.store.tracks.isEmpty)
        #expect(fixture.session.store.trashOperations.count == 1)
    }

    @Test("An album can be trashed, restored, and deleted permanently")
    func trashAlbum() async throws {
        let fixture = try TrashFixture()
        defer { fixture.remove() }

        let repository = LibraryRepository(
            modelContainer: fixture.container
        )
        let operationID = try await repository.trash(
            targetKind: .album,
            targetID: fixture.albumID,
            location: fixture.location
        )

        let operations = try await repository.trashOperations()
        let trashed = try #require(operations.first)
        #expect(trashed.id == operationID)
        #expect(trashed.targetKind == .album)
        #expect(Set(trashed.targetIDs) == Set(fixture.trackIDs))
        #expect(trashed.relativePaths.count == fixture.managedPaths.count)
        #expect(try await repository.tracksPage().items.isEmpty)
        #expect(try await repository.albumsPage().items.isEmpty)
        #expect(try await repository.artistsPage().items.isEmpty)
        #expect(
            try ModelContext(fixture.container).fetch(
                FetchDescriptor<PlaylistEntryRecord>()
            ).isEmpty
        )
        try fixture.requireMovedFiles(operationID: operationID)

        try await repository.restoreTrash(
            operationID: operationID,
            location: fixture.location
        )
        #expect(try await repository.trashOperations().isEmpty)
        #expect(try await repository.tracksPage().items.count == 3)
        #expect(try await repository.albumsPage().items.count == 1)
        #expect(try await repository.artistsPage().items.count == 1)
        #expect(
            try await repository.playlistTracks(
                playlistID: fixture.playlistID
            ).map(\.id) == fixture.trackIDs
        )
        try fixture.requireRestoredFiles(operationID: operationID)
        try fixture.requireRestoredMetadata()

        let secondOperationID = try await repository.trash(
            targetKind: .album,
            targetID: fixture.albumID,
            location: fixture.location
        )
        try await repository.emptyTrash(location: fixture.location)
        #expect(try await repository.trashOperations().isEmpty)
        #expect(!fixture.operationDirectory(secondOperationID).fileExists)
    }

    @Test("Multiple selected tracks move to Trash in one bulk request")
    func trashSelectedTracks() async throws {
        let fixture = try TrashFixture()
        defer { fixture.remove() }
        let repository = LibraryRepository(
            modelContainer: fixture.container
        )

        let operationIDs = try await repository.trashTracks(
            targetIDs: Array(fixture.trackIDs.prefix(2)),
            location: fixture.location
        )

        #expect(operationIDs.count == 2)
        #expect(try await repository.tracksPage().items.count == 1)
        #expect(try await repository.trashOperations().count == 2)
    }
}

private struct SharedArtistTrashFixture {
    let root: URL
    let location: ManagedLibraryLocation
    let container: ModelContainer
    let primaryArtistID: UUID
    let mediaURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Shared-Artist-Trash-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        location = ManagedLibraryLocation(musicDirectory: root)
        try ManagedLibraryPackage(location: location)
            .bootstrapForConfirmedImport()
        container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let primary = ArtistRecord(name: "madkid", trackCount: 1, albumCount: 1)
        let secondary = ArtistRecord(name: "темный принц", trackCount: 1)
        let album = AlbumRecord(
            title: "Shared",
            artist: primary,
            trackCount: 1,
            totalDuration: 180
        )
        let trackID = UUID()
        let mediaPath = "Media/\(trackID.uuidString).flac"
        let track = TrackRecord(
            id: trackID,
            originalFilename: "Joint Signal.flac",
            title: "Joint Signal",
            duration: 180,
            codec: "FLAC",
            container: "FLAC",
            sampleRate: 48000,
            channelCount: 2,
            contentHash: String(repeating: "9", count: 64),
            relativeMediaPath: mediaPath,
            importSessionID: UUID(),
            artist: primary,
            album: album
        )
        context.insert(primary)
        context.insert(secondary)
        context.insert(album)
        context.insert(track)
        context.insert(
            TrackArtistCreditRecord(
                track: track,
                artist: primary,
                position: 0,
                displayArtistName: "madkid, темный принц"
            )
        )
        context.insert(
            TrackArtistCreditRecord(
                track: track,
                artist: secondary,
                position: 1,
                displayArtistName: "madkid, темный принц"
            )
        )
        try context.save()
        primaryArtistID = primary.id
        mediaURL = try location.resolve(relativePath: mediaPath)
        try Data("audio".utf8).write(to: mediaURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class DeletionHandoffFixture {
    let root: URL
    let session: LibrarySession
    let albumID: UUID

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Deletion-Handoff-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let musicDirectory = root.appending(
            path: "Music",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: musicDirectory,
            withIntermediateDirectories: true
        )
        let location = ManagedLibraryLocation(musicDirectory: musicDirectory)
        let package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        let container = try LibraryContainerFactory.persistent(package: package)
        let context = ModelContext(container)
        let artist = ArtistRecord(name: "Captured Artist", trackCount: 1, albumCount: 1)
        let album = AlbumRecord(title: "Captured Album", artist: artist, trackCount: 1)
        let trackID = UUID()
        let mediaPath = "Media/\(trackID.uuidString).flac"
        let track = TrackRecord(
            id: trackID,
            originalFilename: "Captured.flac",
            title: "Captured Track",
            duration: 1,
            codec: "FLAC",
            container: "flac",
            sampleRate: 44100,
            channelCount: 2,
            contentHash: String(repeating: "c", count: 64),
            relativeMediaPath: mediaPath,
            importSessionID: UUID(),
            artist: artist,
            album: album
        )
        context.insert(artist)
        context.insert(album)
        context.insert(track)
        try context.save()
        try Data("audio".utf8).write(to: location.resolve(relativePath: mediaPath))
        albumID = album.id
        session = LibrarySession.startup(location: location)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct TrashFixture {
    private struct SeedResult {
        let albumID: UUID
        let playlistID: UUID
        let managedPaths: [String]
    }

    let root: URL
    let location: ManagedLibraryLocation
    let container: ModelContainer
    let albumID: UUID
    let playlistID: UUID
    let trackIDs: [UUID]
    let managedPaths: [String]

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Trash-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        location = ManagedLibraryLocation(musicDirectory: root)
        try ManagedLibraryPackage(location: location)
            .bootstrapForConfirmedImport()
        container = try LibraryContainerFactory.inMemory()

        let ids = (0 ..< 3).map { _ in UUID() }
        let seeded = try Self.seed(container: container, trackIDs: ids)
        albumID = seeded.albumID
        playlistID = seeded.playlistID
        trackIDs = ids
        managedPaths = seeded.managedPaths
        for path in managedPaths {
            try Data(path.utf8).write(
                to: location.resolve(relativePath: path)
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func requireMovedFiles(operationID: UUID) throws {
        for path in managedPaths {
            let original = try location.resolve(relativePath: path)
            let trashed = try location.resolve(
                relativePath: "Trash/\(operationID.uuidString)/\(path)"
            )
            #expect(!original.fileExists)
            #expect(trashed.fileExists)
        }
        #expect(
            operationDirectory(operationID)
                .appending(path: "manifest.json")
                .fileExists
        )
    }

    func requireRestoredFiles(operationID: UUID) throws {
        for path in managedPaths {
            let original = try location.resolve(relativePath: path)
            #expect(original.fileExists)
        }
        #expect(!operationDirectory(operationID).fileExists)
    }

    func requireRestoredMetadata() throws {
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<LyricRecord>()).count == 1)
        #expect(
            try context.fetch(
                FetchDescriptor<TagAssignmentRecord>()
            ).count == 1
        )
    }

    func operationDirectory(_ operationID: UUID) -> URL {
        ManagedLibraryPackage(location: location)
            .trashDirectoryURL.appending(
                path: operationID.uuidString,
                directoryHint: .isDirectory
            )
    }

    private static func seed(
        container: ModelContainer,
        trackIDs: [UUID]
    ) throws -> SeedResult {
        let context = ModelContext(container)
        let artist = ArtistRecord(
            name: "Trash Artist",
            trackCount: trackIDs.count,
            albumCount: 1
        )
        let album = AlbumRecord(
            title: "Trash Album",
            artist: artist,
            trackCount: trackIDs.count
        )
        let session = ImportSessionRecord(
            sourceDisplayName: "Trash Fixture",
            state: .complete,
            importedCount: trackIDs.count
        )
        context.insert(session)
        context.insert(artist)
        context.insert(album)

        let seededTracks = makeTracks(
            context: context,
            trackIDs: trackIDs,
            sessionID: session.id,
            artist: artist,
            album: album
        )
        let playlist = PlaylistRecord(name: "Trash Recovery")
        context.insert(playlist)
        for (position, trackID) in trackIDs.enumerated() {
            context.insert(
                PlaylistEntryRecord(
                    playlistID: playlist.id,
                    trackID: trackID,
                    position: position
                )
            )
        }
        let lyricPath = addRelatedMetadata(
            context: context,
            track: seededTracks.records[0],
            album: album
        )
        try context.save()
        return SeedResult(
            albumID: album.id,
            playlistID: playlist.id,
            managedPaths: seededTracks.paths + [lyricPath]
        )
    }

    private static func makeTracks(
        context: ModelContext,
        trackIDs: [UUID],
        sessionID: UUID,
        artist: ArtistRecord,
        album: AlbumRecord
    ) -> (records: [TrackRecord], paths: [String]) {
        var records: [TrackRecord] = []
        let paths = trackIDs.enumerated().map { index, id in
            let path = "Media/\(id.uuidString).flac"
            let track = TrackRecord(
                id: id,
                originalFilename: "\(id.uuidString).flac",
                title: id.uuidString,
                duration: 1,
                codec: "FLAC",
                container: "FLAC",
                sampleRate: 44100,
                channelCount: 2,
                contentHash: String(format: "%064x", index + 1),
                relativeMediaPath: path,
                importSessionID: sessionID,
                artist: artist,
                album: album
            )
            context.insert(track)
            records.append(track)
            return path
        }
        return (records, paths)
    }

    private static func addRelatedMetadata(
        context: ModelContext,
        track: TrackRecord,
        album: AlbumRecord
    ) -> String {
        let lyricPath = "Lyrics/\(track.id.uuidString).lrc"
        context.insert(
            LyricRecord(
                relativePath: lyricPath,
                contentHash: String(repeating: "a", count: 64),
                timingStatus: .synchronized,
                track: track
            )
        )
        let tag = TagRecord(displayPath: "mood/calm")
        context.insert(tag)
        context.insert(
            TagAssignmentRecord(
                targetKind: .album,
                targetID: album.id,
                tagID: tag.id
            )
        )
        return lyricPath
    }
}

private extension URL {
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
