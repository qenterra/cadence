import AppKit
@testable import Cadence
import Foundation
import SwiftData
import SwiftUI
import Testing

// These deterministic collection fixtures stay compact when each nested rule
// keeps its trailing comma alongside the surrounding fixture structure.
// swiftlint:disable trailing_comma

extension DocumentationScreenshotFixture {
    struct SeededLibrary {
        let tracks: [TrackRecord]
        let albumID: UUID
        let artistID: UUID
        let tagID: UUID
        let emptyPlaylistID: UUID
    }

    func installLongLocalizedHomeMetadata() {
        let store = model.librarySession.store
        let recentTracks = store.recentlyPlayedTracks.enumerated()
        store.recentlyPlayedTracks = recentTracks.map { index, track in
            track.replacingHomeMetadata(
                title: index.isMultiple(of: 2)
                    ? "Сигналы, которые остаются после полуночи"
                    : "Путешествие сквозь очень тихий зимний город",
                artist: "Северный экспериментальный ансамбль"
            )
        }
        let favoriteTracks = store.favoriteTracks.enumerated()
        store.favoriteTracks = favoriteTracks.map { index, track in
            track.replacingHomeMetadata(
                title: index.isMultiple(of: 2)
                    ? "Архитектура исчезающего света"
                    : "Возвращение к дальним спутникам",
                artist: "Оркестр стеклянного района"
            )
        }
    }

    static func seed(
        _ container: ModelContainer
    ) async throws -> SeededLibrary {
        let context = ModelContext(container)
        let importID = screenshotUUID(0x601)
        let artists = makeArtists()
        let albums = makeAlbums(artists: artists)
        let tracks = makeTracks(albums: albums, importID: importID)
        let tag = TagRecord(
            id: screenshotUUID(0x501),
            displayPath: "context/late night",
            groupPath: "context"
        )
        let ambientTag = TagRecord(
            id: screenshotUUID(0x502),
            displayPath: "genre/ambient",
            groupPath: "genre"
        )
        persist(
            artists: artists,
            albums: albums,
            tracks: tracks,
            tags: [tag, ambientTag],
            context: context
        )
        try context.save()
        let repository = LibraryRepository(modelContainer: container)
        for collection in smartCollections {
            try await repository.saveSmartCollection(collection)
        }
        let populatedPlaylist = try await repository.createPlaylist(
            name: "Night Drive"
        )
        try await repository.addToPlaylist(
            playlistID: populatedPlaylist.id,
            trackIDs: tracks.prefix(5).map(\.id)
        )
        let emptyPlaylist = try await repository.createPlaylist(
            name: "Quiet Queue"
        )

        return SeededLibrary(
            tracks: tracks,
            albumID: albums[0].id,
            artistID: artists[0].id,
            tagID: tag.id,
            emptyPlaylistID: emptyPlaylist.id
        )
    }

    static let smartCollections: [SmartCollectionPreview] = [
        SmartCollectionPreview(
            id: UUID(uuidString: "CA000000-0000-0000-0000-000000000101")!,
            name: "Late Night Focus",
            userDescription: "Quiet, spacious tracks for working after dark.",
            rule: SmartCollectionRuleGroup(
                id: UUID(uuidString: "CA000000-0000-0000-0000-000000000111")!,
                combinator: .all,
                children: [
                    .condition(
                        SmartCollectionRuleCondition(
                            id: UUID(uuidString: "CA000000-0000-0000-0000-000000000121")!,
                            field: .format,
                            operator: .is,
                            value: .text("FLAC")
                        )
                    ),
                ]
            ),
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000)
        ),
        SmartCollectionPreview(
            id: UUID(uuidString: "CA000000-0000-0000-0000-000000000102")!,
            name: "Ambient Favorites",
            rule: SmartCollectionRuleGroup(
                id: UUID(uuidString: "CA000000-0000-0000-0000-000000000112")!,
                combinator: .all,
                children: [
                    .condition(
                        SmartCollectionRuleCondition(
                            id: UUID(uuidString: "CA000000-0000-0000-0000-000000000122")!,
                            field: .favorite,
                            operator: .is,
                            value: .boolean(true)
                        )
                    ),
                ]
            ),
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_001)
        ),
        SmartCollectionPreview(
            id: UUID(uuidString: "CA000000-0000-0000-0000-000000000103")!,
            name: "Signals After Dark",
            rule: SmartCollectionRuleGroup(
                id: UUID(uuidString: "CA000000-0000-0000-0000-000000000113")!,
                combinator: .all,
                children: [
                    .condition(
                        SmartCollectionRuleCondition(
                            id: UUID(uuidString: "CA000000-0000-0000-0000-000000000123")!,
                            field: .year,
                            operator: .greaterThan,
                            value: .integer(2024)
                        )
                    ),
                ]
            ),
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_002)
        ),
        SmartCollectionPreview(
            id: UUID(uuidString: "CA000000-0000-0000-0000-000000000104")!,
            name: "High Resolution",
            rule: SmartCollectionRuleGroup(
                id: UUID(uuidString: "CA000000-0000-0000-0000-000000000114")!,
                combinator: .all,
                children: [.condition(.init(
                    id: UUID(uuidString: "CA000000-0000-0000-0000-000000000124")!,
                    field: .artist,
                    operator: .contains,
                    value: .text("North")
                ))]
            ),
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_003)
        ),
        SmartCollectionPreview(
            id: UUID(uuidString: "CA000000-0000-0000-0000-000000000105")!,
            name: "Recent Signals",
            rule: SmartCollectionRuleGroup(
                id: UUID(uuidString: "CA000000-0000-0000-0000-000000000115")!,
                combinator: .all,
                children: [.condition(.init(
                    id: UUID(uuidString: "CA000000-0000-0000-0000-000000000125")!,
                    field: .year,
                    operator: .greaterThan,
                    value: .integer(2025)
                ))]
            ),
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_004)
        ),
        SmartCollectionPreview(
            id: UUID(uuidString: "CA000000-0000-0000-0000-000000000106")!,
            name: "Longform",
            rule: SmartCollectionRuleGroup(
                id: UUID(uuidString: "CA000000-0000-0000-0000-000000000116")!,
                combinator: .all,
                children: [.condition(.init(
                    id: UUID(uuidString: "CA000000-0000-0000-0000-000000000126")!,
                    field: .album,
                    operator: .contains,
                    value: .text("Signals")
                ))]
            ),
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_005)
        ),
        SmartCollectionPreview(
            id: UUID(uuidString: "CA000000-0000-0000-0000-000000000107")!,
            name: "Stereo Masters",
            rule: SmartCollectionRuleGroup(
                id: UUID(uuidString: "CA000000-0000-0000-0000-000000000117")!,
                combinator: .all,
                children: [.condition(.init(
                    id: UUID(uuidString: "CA000000-0000-0000-0000-000000000127")!,
                    field: .year,
                    operator: .lessThan,
                    value: .integer(2026)
                ))]
            ),
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_006)
        ),
        SmartCollectionPreview(
            id: UUID(uuidString: "CA000000-0000-0000-0000-000000000108")!,
            name: "Deep Archive",
            rule: SmartCollectionRuleGroup(
                id: UUID(uuidString: "CA000000-0000-0000-0000-000000000118")!,
                combinator: .all,
                children: [.condition(.init(
                    id: UUID(uuidString: "CA000000-0000-0000-0000-000000000128")!,
                    field: .format,
                    operator: .is,
                    value: .text("FLAC")
                ))]
            ),
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_007)
        ),
    ]

    static func makeTracks(
        albums: [AlbumRecord],
        importID: UUID
    ) -> [TrackRecord] {
        trackTitles.enumerated().map { index, title in
            let album = albums[index / 3]
            return TrackRecord(
                id: screenshotUUID(0x400 + index),
                originalFilename: "synthetic-\(index).flac",
                title: title,
                duration: 210 + Double(index * 9),
                codec: "FLAC",
                container: "flac",
                sampleRate: 96000,
                channelCount: 2,
                bitDepth: 24,
                contentHash: String(format: "%064x", index + 1),
                relativeMediaPath: "Media/synthetic-\(index).flac",
                importSessionID: importID,
                artist: album.artist,
                album: album,
                trackNumber: index % 3 + 1,
                lastPlayedAt: index < 7
                    ? Date(timeIntervalSince1970: 1_800_000_000 - Double(index))
                    : nil,
                isFavorite: index < 4,
                spatialFormat: .stereo
            )
        }
    }

    static func persist(
        artists: [ArtistRecord],
        albums: [AlbumRecord],
        tracks: [TrackRecord],
        tags: [TagRecord],
        context: ModelContext
    ) {
        artists.forEach(context.insert)
        albums.forEach(context.insert)
        tracks.forEach(context.insert)
        tags.forEach(context.insert)
        for (index, item) in tracks.prefix(7).enumerated() {
            context.insert(
                TagAssignmentRecord(
                    id: screenshotUUID(0x700 + index),
                    targetKind: .track,
                    targetID: item.id,
                    tagID: tags[0].id
                )
            )
        }
    }

    static let trackTitles = [
        "Midnight Static",
        "Glass Horizon",
        "Transmission Lines",
        "Fade in the Distance",
        "Hollow Frequency",
        "Afterimage",
        "Distant Satellites",
        "Static Bloom",
        "Quiet Return",
        "Night Windows",
        "Falling Signals",
        "Approaching Light",
    ]

    static func makeArtists() -> [ArtistRecord] {
        [
            ArtistRecord(
                id: screenshotUUID(0x201),
                name: "North Assembly",
                isFavorite: true,
                favoriteDate: Date(timeIntervalSince1970: 1_800_000_000),
                trackCount: 6,
                albumCount: 2
            ),
            ArtistRecord(
                id: screenshotUUID(0x202),
                name: "Glass District",
                trackCount: 3,
                albumCount: 1
            ),
            ArtistRecord(
                id: screenshotUUID(0x203),
                name: "Mara Vale",
                trackCount: 3,
                albumCount: 1
            ),
        ]
    }

    static func makeAlbums(
        artists: [ArtistRecord]
    ) -> [AlbumRecord] {
        [
            AlbumRecord(
                id: screenshotUUID(0x301),
                title: "Signals After Dark",
                artist: artists[0],
                year: 2026,
                isFavorite: true,
                favoriteDate: Date(timeIntervalSince1970: 1_800_000_000),
                trackCount: 3,
                totalDuration: 657
            ),
            AlbumRecord(
                id: screenshotUUID(0x302),
                title: "Coastal Machines",
                artist: artists[0],
                year: 2025,
                trackCount: 3,
                totalDuration: 738
            ),
            AlbumRecord(
                id: screenshotUUID(0x303),
                title: "Glass Horizon",
                artist: artists[1],
                year: 2024,
                trackCount: 3,
                totalDuration: 819
            ),
            AlbumRecord(
                id: screenshotUUID(0x304),
                title: "Transient Lines",
                artist: artists[2],
                year: 2026,
                trackCount: 3,
                totalDuration: 900
            ),
        ]
    }

    private static func screenshotUUID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "CA000000-0000-0000-0000-%012llX",
                UInt64(value)
            )
        )!
    }
}

// swiftlint:enable trailing_comma
