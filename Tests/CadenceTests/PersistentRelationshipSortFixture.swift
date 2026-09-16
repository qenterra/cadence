@testable import Cadence
import Foundation
import SwiftData

final class PersistentRelationshipSortFixture {
    let root: URL
    let container: ModelContainer
    let albumDescendingIDs: [UUID]
    let yearAscendingIDs: [UUID]

    init(
        root: URL,
        container: ModelContainer,
        albumDescendingIDs: [UUID],
        yearAscendingIDs: [UUID]
    ) {
        self.root = root
        self.container = container
        self.albumDescendingIDs = albumDescendingIDs
        self.yearAscendingIDs = yearAscendingIDs
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

extension PersistentRelationshipSortFixture {
    static func make() throws -> PersistentRelationshipSortFixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CadenceRelationshipSort-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let container = try makeContainer(root: root)
        let expected = try populate(container: container)
        return PersistentRelationshipSortFixture(
            root: root,
            container: container,
            albumDescendingIDs: expected.albumDescendingIDs,
            yearAscendingIDs: expected.yearAscendingIDs
        )
    }
}

private extension PersistentRelationshipSortFixture {
    struct ExpectedOrder {
        let albumDescendingIDs: [UUID]
        let yearAscendingIDs: [UUID]
    }

    struct Albums {
        let alpha: AlbumRecord
        let beta: AlbumRecord
        let betaWithoutYear: AlbumRecord
    }

    struct TrackGroups {
        var alpha: [UUID] = []
        var beta: [UUID] = []
        var betaWithoutYear: [UUID] = []
        var missingAlbum: [UUID] = []
    }

    static func makeContainer(root: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV5.self)
        let configuration = ModelConfiguration(
            "CadenceRelationshipSort",
            schema: schema,
            url: root.appending(path: "Catalog.store"),
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: CadenceMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func populate(container: ModelContainer) throws -> ExpectedOrder {
        let context = ModelContext(container)
        let importID = UUID()
        let artist = ArtistRecord(name: "Relationship Sort Artist")
        let albums = Albums(
            alpha: AlbumRecord(
                title: "Alpha",
                artist: artist,
                year: 2024,
                trackCount: 100
            ),
            beta: AlbumRecord(
                title: "Beta",
                artist: artist,
                year: 2022,
                trackCount: 100
            ),
            betaWithoutYear: AlbumRecord(
                title: "Beta",
                artist: artist,
                trackCount: 100
            )
        )
        insertHeaderRecords(
            context: context,
            importID: importID,
            artist: artist,
            albums: albums
        )
        let groups = insertTracks(
            context: context,
            importID: importID,
            artist: artist,
            albums: albums
        )
        try context.save()
        return expectedOrder(groups: groups)
    }

    static func insertHeaderRecords(
        context: ModelContext,
        importID: UUID,
        artist: ArtistRecord,
        albums: Albums
    ) {
        context.insert(artist)
        context.insert(albums.alpha)
        context.insert(albums.beta)
        context.insert(albums.betaWithoutYear)
        context.insert(
            ImportSessionRecord(
                id: importID,
                sourceDisplayName: "Persistent Relationship Sort Fixture",
                state: .complete,
                importedCount: 401
            )
        )
    }

    static func insertTracks(
        context: ModelContext,
        importID: UUID,
        artist: ArtistRecord,
        albums: Albums
    ) -> TrackGroups {
        var groups = TrackGroups()
        for index in 0 ..< 401 {
            let id = deterministicUUID(index)
            let album = album(
                for: index,
                id: id,
                albums: albums,
                groups: &groups
            )
            let title = String(format: "Relationship Track %03d", index)
            context.insert(
                TrackRecord(
                    id: id,
                    originalFilename: "\(title).flac",
                    title: title,
                    duration: 120,
                    codec: "FLAC",
                    container: "FLAC",
                    sampleRate: 48000,
                    channelCount: 2,
                    contentHash: String(format: "%064x", index + 1),
                    relativeMediaPath: "Media/\(id.uuidString).flac",
                    importSessionID: importID,
                    artist: artist,
                    album: album
                )
            )
        }
        return groups
    }

    static func album(
        for index: Int,
        id: UUID,
        albums: Albums,
        groups: inout TrackGroups
    ) -> AlbumRecord? {
        switch index {
        case 0 ..< 100:
            groups.alpha.append(id)
            return albums.alpha
        case 100 ..< 200:
            groups.beta.append(id)
            return albums.beta
        case 200 ..< 300:
            groups.betaWithoutYear.append(id)
            return albums.betaWithoutYear
        default:
            groups.missingAlbum.append(id)
            return nil
        }
    }

    static func expectedOrder(groups: TrackGroups) -> ExpectedOrder {
        let betaTitleIDs = (groups.beta + groups.betaWithoutYear).sorted {
            $0.uuidString < $1.uuidString
        }
        let missingYearIDs = (
            groups.betaWithoutYear + groups.missingAlbum
        ).sorted {
            $0.uuidString < $1.uuidString
        }
        return ExpectedOrder(
            albumDescendingIDs: betaTitleIDs + groups.alpha
                + groups.missingAlbum,
            yearAscendingIDs: missingYearIDs + groups.beta + groups.alpha
        )
    }

    static func deterministicUUID(_ index: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                index + 1
            )
        ) ?? UUID()
    }
}
