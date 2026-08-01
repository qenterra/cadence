import Foundation
import SwiftData

@ModelActor
actor LibraryRepository {
    static let maximumPageSize = 200

    func tracksPage(
        after cursor: LibraryPageCursor? = nil,
        search: String? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryTrackProjection> {
        try tracksPage(
            query: LibraryTrackQuery(search: search ?? ""),
            after: cursor,
            limit: limit
        )
    }

    func artistsPage(
        after cursor: LibraryPageCursor? = nil,
        search: String? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryArtistProjection> {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        var descriptor = LibraryFetchDescriptors.artists(
            after: cursor,
            search: SearchNormalizer.normalize(search ?? "")
        )
        descriptor.fetchLimit = boundedLimit + 1

        let records = try modelContext.fetch(descriptor)
        return LibraryPageBuilder.page(
            records: records,
            limit: boundedLimit,
            sortValue: \.normalizedName,
            identity: \.sortIdentity,
            projection: LibraryProjectionFactory.artist
        )
    }

    func albumsPage(
        after cursor: LibraryPageCursor? = nil,
        search: String? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryAlbumProjection> {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        var descriptor = LibraryFetchDescriptors.albums(
            after: cursor,
            search: SearchNormalizer.normalize(search ?? "")
        )
        descriptor.fetchLimit = boundedLimit + 1

        let records = try modelContext.fetch(descriptor)
        return LibraryPageBuilder.page(
            records: records,
            limit: boundedLimit,
            sortValue: \.normalizedTitle,
            identity: \.sortIdentity,
            projection: LibraryProjectionFactory.album
        )
    }

    func playbackTracks(ids: [UUID]) throws -> [PlaybackTrack] {
        guard !ids.isEmpty else {
            return []
        }

        let requestedIDs = Array(Set(ids))
        let predicate = #Predicate<TrackRecord> { track in
            requestedIDs.contains(track.id)
        }
        let records = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
        let recordsByID = Dictionary(
            uniqueKeysWithValues: records.map { ($0.id, $0) }
        )

        return ids.compactMap {
            recordsByID[$0].map(LibraryProjectionFactory.playback)
        }
    }

    func allTrackIDs() throws -> [UUID] {
        try modelContext.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [
                    SortDescriptor(\.normalizedTitle),
                    SortDescriptor(\.sortIdentity),
                ]
            )
        )
        .map(\.id)
    }

    func containsExactHash(_ contentHash: String) throws -> Bool {
        let predicate = #Predicate<TrackRecord> { track in
            track.contentHash == contentHash
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    func importDuplicateEvidence(
        probes: [ImportDuplicateProbe]
    ) throws -> ImportDuplicateEvidence {
        guard !probes.isEmpty else {
            return .empty
        }

        let hashes = Array(Set(probes.map(\.contentHash)))
        let identities = Set(probes.map(\.identity))
        let titles = Array(Set(identities.map(\.normalizedTitle)))
        return try ImportDuplicateEvidence(
            exactHashes: committedHashes(in: hashes),
            metadataIdentities: committedMetadataIdentities(
                in: titles,
                requested: identities
            )
        )
    }

    private func committedHashes(
        in hashes: [String]
    ) throws -> Set<String> {
        var matches: Set<String> = []
        for hashChunk in hashes.chunked(maximumCount: 100) {
            let predicate = #Predicate<TrackRecord> { track in
                hashChunk.contains(track.contentHash)
            }
            var descriptor = FetchDescriptor(predicate: predicate)
            descriptor.fetchLimit = hashChunk.count
            try matches.formUnion(
                modelContext.fetch(descriptor).map(\.contentHash)
            )
        }
        return matches
    }

    private func committedMetadataIdentities(
        in titles: [String],
        requested identities: Set<ImportMetadataIdentity>
    ) throws -> Set<ImportMetadataIdentity> {
        var matches: Set<ImportMetadataIdentity> = []
        for titleChunk in titles.chunked(maximumCount: 100) {
            var offset = 0
            while true {
                let predicate = #Predicate<TrackRecord> { track in
                    titleChunk.contains(track.normalizedTitle)
                }
                var descriptor = FetchDescriptor(
                    predicate: predicate,
                    sortBy: [
                        SortDescriptor(\.normalizedTitle),
                        SortDescriptor(\.sortIdentity),
                    ]
                )
                descriptor.fetchLimit = Self.maximumPageSize
                descriptor.fetchOffset = offset
                let page = try modelContext.fetch(descriptor)

                for track in page {
                    let identity = ImportMetadataIdentity(
                        normalizedArtist: track.artist?.normalizedName
                            ?? SearchNormalizer.normalize("Unknown Artist"),
                        normalizedTitle: track.normalizedTitle
                    )
                    if identities.contains(identity) {
                        matches.insert(identity)
                    }
                }

                guard page.count == Self.maximumPageSize else {
                    break
                }
                offset += page.count
            }
        }
        return matches
    }
}

private extension Array {
    func chunked(
        maximumCount: Int
    ) -> [[Element]] {
        guard !isEmpty else {
            return []
        }
        return stride(from: 0, to: count, by: maximumCount).map {
            Array(self[$0 ..< Swift.min($0 + maximumCount, count)])
        }
    }
}
