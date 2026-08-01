import Foundation
import SwiftData

private struct ProductionSmartCollectionRecords {
    let tracks: [TrackRecord]
    let assignments: [TagAssignmentRecord]
    let exclusions: [TagExclusionRecord]
    let tags: [TagRecord]
}

extension LibraryRepository {
    func productionSmartCollectionRuleData() throws
        -> ProductionSmartCollectionRuleData {
        let tags = try modelContext.fetch(
            FetchDescriptor<TagRecord>(
                sortBy: [SortDescriptor(\.normalizedPath)]
            )
        ).map(LibraryProjectionFactory.tag)
        let artists = try modelContext.fetch(
            FetchDescriptor<ArtistRecord>(
                sortBy: [SortDescriptor(\.normalizedName)]
            )
        ).map(\.name)
        let albums = try modelContext.fetch(
            FetchDescriptor<AlbumRecord>(
                sortBy: [SortDescriptor(\.normalizedTitle)]
            )
        ).map(\.title)
        let tracks = try productionSmartCollectionTrackRecords()
        return ProductionSmartCollectionRuleData(
            options: SmartCollectionRuleOptions(
                tagIDs: tags.map(\.id.uuidString),
                artists: uniqueLocalizedValues(artists),
                albums: uniqueLocalizedValues(albums),
                years: Array(
                    Set(tracks.compactMap { $0.album?.year })
                ).sorted(by: >),
                formats: uniqueLocalizedValues(tracks.map(\.codec))
            ),
            tags: tags
        )
    }

    func evaluateProductionSmartCollection(
        root: SmartCollectionRuleGroup
    ) throws -> ProductionSmartCollectionEvaluation {
        let records = try productionSmartCollectionRecords()
        let tagProjections = records.tags.map(LibraryProjectionFactory.tag)
        let orderedIDs = ProductionSmartCollectionEvaluator().evaluateIDs(
            root: root,
            candidates: smartCollectionCandidates(records: records),
            tagsByID: Dictionary(
                uniqueKeysWithValues: tagProjections.map { ($0.id, $0) }
            )
        )
        let durationByID = Dictionary(
            uniqueKeysWithValues: records.tracks.map { ($0.id, $0.duration) }
        )
        return ProductionSmartCollectionEvaluation(
            orderedTrackIDs: orderedIDs,
            totalDuration: orderedIDs.reduce(0) {
                $0 + (durationByID[$1] ?? 0)
            }
        )
    }

    func productionSmartCollectionTrackPage(
        orderedIDs: [UUID],
        offset: Int = 0,
        limit: Int = maximumPageSize
    ) throws -> ProductionSmartCollectionResultPage {
        let boundedOffset = min(max(offset, 0), orderedIDs.count)
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        let end = min(boundedOffset + boundedLimit, orderedIDs.count)
        let pageIDs = Array(orderedIDs[boundedOffset ..< end])
        let recordsByID = try tagTrackRecordsByID(ids: pageIDs)
        return ProductionSmartCollectionResultPage(
            items: pageIDs.compactMap {
                recordsByID[$0].map(LibraryProjectionFactory.track)
            },
            nextOffset: end < orderedIDs.count ? end : nil
        )
    }
}

private extension LibraryRepository {
    func productionSmartCollectionRecords() throws
        -> ProductionSmartCollectionRecords {
        try ProductionSmartCollectionRecords(
            tracks: productionSmartCollectionTrackRecords(),
            assignments: modelContext.fetch(
                FetchDescriptor<TagAssignmentRecord>()
            ),
            exclusions: modelContext.fetch(
                FetchDescriptor<TagExclusionRecord>()
            ),
            tags: modelContext.fetch(
                FetchDescriptor<TagRecord>(
                    sortBy: [SortDescriptor(\.normalizedPath)]
                )
            )
        )
    }

    func productionSmartCollectionTrackRecords() throws -> [TrackRecord] {
        try modelContext.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [
                    SortDescriptor(\.normalizedTitle),
                    SortDescriptor(\.sortIdentity),
                ]
            )
        )
    }

    func smartCollectionCandidates(
        records: ProductionSmartCollectionRecords
    ) -> [ProductionSmartCollectionCandidate] {
        let directByTrackID = Dictionary(
            grouping: records.assignments.filter { $0.targetKind == .track },
            by: \.targetID
        ).mapValues { Set($0.map(\.tagID)) }
        let inheritedByAlbumID = Dictionary(
            grouping: records.assignments.filter { $0.targetKind == .album },
            by: \.targetID
        ).mapValues { Set($0.map(\.tagID)) }
        let exclusionsByTrackID = Dictionary(
            grouping: records.exclusions,
            by: \.trackID
        ).mapValues { Set($0.map(\.tagID)) }

        return records.tracks.map { track in
            let direct = directByTrackID[track.id] ?? []
            let inherited = track.album.flatMap {
                inheritedByAlbumID[$0.id]
            } ?? []
            let excluded = exclusionsByTrackID[track.id] ?? []
            return ProductionSmartCollectionCandidate(
                id: track.id,
                artist: track.artist?.name ?? "Unknown Artist",
                album: track.album?.title ?? "Unknown Album",
                duration: track.duration,
                year: track.album?.year,
                codec: track.codec,
                isFavorite: track.isFavorite,
                effectiveTagIDs: direct.union(
                    inherited.subtracting(excluded)
                )
            )
        }
    }

    func uniqueLocalizedValues(
        _ values: [String]
    ) -> [String] {
        Array(Set(values)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
