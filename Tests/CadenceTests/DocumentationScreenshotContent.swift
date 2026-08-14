import AppKit
@testable import Cadence
import Foundation
import SwiftData
import SwiftUI
import Testing

extension DocumentationScreenshotFixture {
    struct SeededLibrary {
        let tracks: [TrackRecord]
        let albumID: UUID
        let artistID: UUID
        let tagID: UUID
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
    ) throws -> SeededLibrary {
        let context = ModelContext(container)
        let importID = UUID()
        let artists = makeArtists()
        let albums = makeAlbums(artists: artists)
        let tracks = makeTracks(albums: albums, importID: importID)
        let tag = TagRecord(
            displayPath: "context/late night",
            groupPath: "context"
        )
        let ambientTag = TagRecord(
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

        return SeededLibrary(
            tracks: tracks,
            albumID: albums[0].id,
            artistID: artists[0].id,
            tagID: tag.id
        )
    }

    static func makeTracks(
        albums: [AlbumRecord],
        importID: UUID
    ) -> [TrackRecord] {
        trackTitles.enumerated().map { index, title in
            let album = albums[index / 3]
            return TrackRecord(
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
        for item in tracks.prefix(7) {
            context.insert(
                TagAssignmentRecord(
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
                name: "North Assembly",
                isFavorite: true,
                favoriteDate: Date(timeIntervalSince1970: 1_800_000_000),
                trackCount: 6,
                albumCount: 2
            ),
            ArtistRecord(name: "Glass District", trackCount: 3, albumCount: 1),
            ArtistRecord(name: "Mara Vale", trackCount: 3, albumCount: 1),
        ]
    }

    static func makeAlbums(
        artists: [ArtistRecord]
    ) -> [AlbumRecord] {
        [
            AlbumRecord(
                title: "Signals After Dark",
                artist: artists[0],
                year: 2026,
                isFavorite: true,
                favoriteDate: Date(timeIntervalSince1970: 1_800_000_000),
                trackCount: 3,
                totalDuration: 657
            ),
            AlbumRecord(
                title: "Coastal Machines",
                artist: artists[0],
                year: 2025,
                trackCount: 3,
                totalDuration: 738
            ),
            AlbumRecord(
                title: "Glass Horizon",
                artist: artists[1],
                year: 2024,
                trackCount: 3,
                totalDuration: 819
            ),
            AlbumRecord(
                title: "Transient Lines",
                artist: artists[2],
                year: 2026,
                trackCount: 3,
                totalDuration: 900
            ),
        ]
    }
}
