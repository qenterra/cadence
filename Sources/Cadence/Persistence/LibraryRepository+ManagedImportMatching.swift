import Foundation
import SwiftData

struct ManagedAlbumIdentity: Hashable {
    let normalizedArtist: String
    let normalizedTitle: String
}

extension LibraryRepository {
    func assertImportIsUncommitted(
        importID: UUID,
        entries: [ManagedImportManifest.Entry]
    ) throws {
        let sessionPredicate = #Predicate<ImportSessionRecord> { session in
            session.id == importID
        }
        var sessionDescriptor = FetchDescriptor(
            predicate: sessionPredicate
        )
        sessionDescriptor.fetchLimit = 1
        guard try modelContext.fetch(sessionDescriptor).isEmpty else {
            throw ManagedImportStoreError.duplicateImportSession(importID)
        }

        let trackIDs = entries.map(\.trackID)
        if !trackIDs.isEmpty {
            let trackPredicate = #Predicate<TrackRecord> { track in
                trackIDs.contains(track.id)
            }
            var trackDescriptor = FetchDescriptor(predicate: trackPredicate)
            trackDescriptor.fetchLimit = 1
            if let duplicate = try modelContext.fetch(trackDescriptor).first {
                throw ManagedImportStoreError.duplicateTrack(duplicate.id)
            }
        }

        let hashes = entries.map(\.expectedAudioHash)
        if !hashes.isEmpty {
            let hashPredicate = #Predicate<TrackRecord> { track in
                hashes.contains(track.contentHash)
            }
            var hashDescriptor = FetchDescriptor(predicate: hashPredicate)
            hashDescriptor.fetchLimit = 1
            if let duplicate = try modelContext.fetch(hashDescriptor).first {
                throw ManagedImportStoreError.duplicateContent(
                    duplicate.contentHash
                )
            }
        }
    }

    func reusableArtists(
        for entries: [ManagedImportManifest.Entry]
    ) throws -> [String: ArtistRecord] {
        let sourceNames = entries.flatMap { entry in
            entry.metadata.creditArtistNames
                + [entry.metadata.albumArtistName]
        }
        let names = Array(Set(sourceNames.map(SearchNormalizer.normalize)))
        var artistsByName: [String: ArtistRecord] = [:]
        if !names.isEmpty {
            let predicate = #Predicate<ArtistRecord> { artist in
                names.contains(artist.normalizedName)
            }
            let descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\.sortIdentity)]
            )
            for artist in try modelContext.fetch(descriptor) {
                artistsByName[artist.normalizedName, default: artist] = artist
            }
        }

        for name in sourceNames {
            let normalizedName = SearchNormalizer.normalize(name)
            guard artistsByName[normalizedName] == nil else {
                continue
            }
            let artist = ArtistRecord(name: name)
            modelContext.insert(artist)
            artistsByName[normalizedName] = artist
        }
        return artistsByName
    }

    func reusableAlbums(
        for entries: [ManagedImportManifest.Entry],
        artists: [String: ArtistRecord],
        dateAdded: Date
    ) throws -> [ManagedAlbumIdentity: AlbumRecord] {
        let titles = Array(
            Set(
                entries.map {
                    SearchNormalizer.normalize($0.metadata.album)
                }
            )
        )
        var albumsByIdentity: [ManagedAlbumIdentity: AlbumRecord] = [:]
        if !titles.isEmpty {
            let predicate = #Predicate<AlbumRecord> { album in
                titles.contains(album.normalizedTitle)
            }
            let descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\.sortIdentity)]
            )
            for album in try modelContext.fetch(descriptor) {
                guard let artistName = album.artist?.normalizedName else {
                    continue
                }
                let identity = ManagedAlbumIdentity(
                    normalizedArtist: artistName,
                    normalizedTitle: album.normalizedTitle
                )
                albumsByIdentity[identity, default: album] = album
            }
        }

        for entry in entries {
            let artistName = SearchNormalizer.normalize(
                entry.metadata.albumArtistName
            )
            let identity = ManagedAlbumIdentity(
                normalizedArtist: artistName,
                normalizedTitle: SearchNormalizer.normalize(
                    entry.metadata.album
                )
            )
            guard albumsByIdentity[identity] == nil else {
                continue
            }
            let album = AlbumRecord(
                title: entry.metadata.album,
                artist: artists[artistName],
                year: entry.metadata.year,
                dateAdded: dateAdded
            )
            modelContext.insert(album)
            albumsByIdentity[identity] = album
        }
        return albumsByIdentity
    }

    func refreshAggregateCounts(
        entries: [ManagedImportManifest.Entry],
        artists: [String: ArtistRecord],
        albums: [ManagedAlbumIdentity: AlbumRecord]
    ) {
        var importedTrackCounts: [String: Int] = [:]
        for entry in entries {
            for name in entry.metadata.creditArtistNames {
                importedTrackCounts[SearchNormalizer.normalize(name), default: 0] += 1
            }
        }
        for (artistName, importedTrackCount) in importedTrackCounts {
            guard let artist = artists[artistName] else {
                continue
            }
            artist.trackCount += importedTrackCount
            artist.albumCount = Set(artist.albums.map(\.id)).count
        }

        let groupedByAlbum = Dictionary(grouping: entries) {
            ManagedAlbumIdentity(
                normalizedArtist: SearchNormalizer.normalize(
                    $0.metadata.albumArtistName
                ),
                normalizedTitle: SearchNormalizer.normalize(
                    $0.metadata.album
                )
            )
        }
        for (identity, importedEntries) in groupedByAlbum {
            guard let album = albums[identity] else {
                continue
            }
            album.trackCount += importedEntries.count
            album.totalDuration += importedEntries.reduce(0) {
                $0 + $1.metadata.duration
            }
        }
    }
}
