import Foundation
import SwiftData

extension LibraryRepository {
    func tagTrackRecordsByID(
        ids: [UUID]
    ) throws -> [UUID: TrackRecord] {
        var recordsByID: [UUID: TrackRecord] = [:]
        for idChunk in tagPredicateChunks(ids) {
            let predicate = #Predicate<TrackRecord> {
                idChunk.contains($0.id)
            }
            let records = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            )
            for record in records {
                recordsByID[record.id] = record
            }
        }
        return recordsByID
    }

    func tagAlbumRecords(
        ids: [UUID]
    ) throws -> [AlbumRecord] {
        var records: [AlbumRecord] = []
        for idChunk in tagPredicateChunks(ids) {
            let predicate = #Predicate<AlbumRecord> {
                idChunk.contains($0.id)
            }
            try records.append(
                contentsOf: modelContext.fetch(
                    FetchDescriptor(predicate: predicate)
                )
            )
        }
        return records
    }

    func tagPredicateChunks<Element>(
        _ values: [Element]
    ) -> [[Element]] {
        let maximumCount = 100
        guard !values.isEmpty else {
            return []
        }
        return stride(from: 0, to: values.count, by: maximumCount).map {
            Array(values[$0 ..< min($0 + maximumCount, values.count)])
        }
    }

    func tracksForTagPicker(
        after cursor: LibraryPageCursor? = nil,
        search: String? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryTrackProjection> {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        var descriptor = tagPickerDescriptor(
            after: cursor,
            search: SearchNormalizer.normalize(search ?? "")
        )
        descriptor.fetchLimit = boundedLimit + 1
        return try trackPage(
            records: modelContext.fetch(descriptor),
            limit: boundedLimit,
            sortValue: \.normalizedTitle,
            identity: \.sortIdentity
        )
    }

    func directlyAssignedTrackIDs(
        tagID: UUID
    ) throws -> Set<UUID> {
        let targetKind = TagTargetKind.track.rawValue
        let predicate = #Predicate<TagAssignmentRecord> {
            $0.tagID == tagID
                && $0.targetKindRawValue == targetKind
        }
        return try Set(
            modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            )
            .map(\.targetID)
        )
    }

    func assignTag(
        _ tagID: UUID,
        trackIDs: [UUID]
    ) throws {
        let requestedIDs = Array(Set(trackIDs))
        guard !requestedIDs.isEmpty else {
            return
        }
        guard try containsTag(id: tagID) else {
            throw ProductionTagEditError.missingTag
        }

        let liveTrackIDs = try Set(
            tagTrackRecordsByID(ids: requestedIDs).keys
        )
        guard liveTrackIDs.count == requestedIDs.count else {
            throw ProductionTagEditError.missingTracks
        }

        let existingIDs = try existingDirectAssignmentIDs(
            tagID: tagID,
            trackIDs: requestedIDs
        )

        for trackID in requestedIDs where !existingIDs.contains(trackID) {
            modelContext.insert(
                TagAssignmentRecord(
                    targetKind: .track,
                    targetID: trackID,
                    tagID: tagID
                )
            )
        }
        try modelContext.save()
    }

    private func containsTag(id: UUID) throws -> Bool {
        let predicate = #Predicate<TagRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func tagPickerDescriptor(
        after cursor: LibraryPageCursor?,
        search: String
    ) -> FetchDescriptor<TrackRecord> {
        let sort = [
            SortDescriptor(\TrackRecord.normalizedTitle),
            SortDescriptor(\TrackRecord.sortIdentity),
        ]
        if let cursor {
            let cursorValue = cursor.sortValue
            let cursorIdentity = cursor.identity
            let predicate = #Predicate<TrackRecord> { record in
                (
                    search.isEmpty
                        || record.normalizedTitle.contains(search)
                        || record.artist?.normalizedName.contains(search) == true
                        || record.album?.normalizedTitle.contains(search) == true
                )
                    && (
                        record.normalizedTitle > cursorValue
                            || (
                                record.normalizedTitle == cursorValue
                                    && record.sortIdentity > cursorIdentity
                            )
                    )
            }
            return FetchDescriptor(predicate: predicate, sortBy: sort)
        }
        guard !search.isEmpty else {
            return FetchDescriptor(sortBy: sort)
        }
        let predicate = #Predicate<TrackRecord> { record in
            record.normalizedTitle.contains(search)
                || record.artist?.normalizedName.contains(search) == true
                || record.album?.normalizedTitle.contains(search) == true
        }
        return FetchDescriptor(predicate: predicate, sortBy: sort)
    }

    private func existingDirectAssignmentIDs(
        tagID: UUID,
        trackIDs: [UUID]
    ) throws -> Set<UUID> {
        let targetKind = TagTargetKind.track.rawValue
        var existingIDs: Set<UUID> = []
        for idChunk in tagPredicateChunks(trackIDs) {
            let predicate = #Predicate<TagAssignmentRecord> {
                $0.tagID == tagID
                    && idChunk.contains($0.targetID)
                    && $0.targetKindRawValue == targetKind
            }
            try existingIDs.formUnion(
                modelContext.fetch(
                    FetchDescriptor(predicate: predicate)
                ).map(\.targetID)
            )
        }
        return existingIDs
    }
}
