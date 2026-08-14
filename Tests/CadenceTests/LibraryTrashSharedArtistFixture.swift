@testable import Cadence
import Foundation
import SwiftData
import Testing

struct SharedArtistTrashFixture {
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
        let seed = try Self.seed(container: container)
        primaryArtistID = seed.artistID
        mediaURL = try location.resolve(relativePath: seed.mediaPath)
        try Data("audio".utf8).write(to: mediaURL)
    }

    private static func seed(
        container: ModelContainer
    ) throws -> (artistID: UUID, mediaPath: String) {
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
        return (primary.id, mediaPath)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

func verifyRestoredSharedArtist(
    context: ModelContext,
    fixture: SharedArtistTrashFixture
) throws {
    let artists = try context.fetch(FetchDescriptor<ArtistRecord>())
    let credits = try context.fetch(
        FetchDescriptor<TrackArtistCreditRecord>(
            sortBy: [SortDescriptor(\.position)]
        )
    )
    let namesByID = Dictionary(
        uniqueKeysWithValues: artists.map { ($0.id, $0.name) }
    )
    #expect(Set(artists.map(\.name)) == ["madkid", "темный принц"])
    #expect(credits.map { namesByID[$0.artistID] } == ["madkid", "темный принц"])
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

@MainActor
final class DeletionHandoffFixture {
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
        try package.writeIdentity(LibraryIdentity())
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
