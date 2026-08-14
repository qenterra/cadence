@testable import Cadence
import Foundation
import SwiftData
import Testing

struct TrashFixture {
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

extension URL {
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
