import Foundation
import SwiftData

extension LibraryRepository {
    func tracksForTagPicker(
        after cursor: LibraryPageCursor? = nil,
        search: String? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryTrackProjection> {
        try tracksPage(
            after: cursor,
            search: search,
            limit: limit
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
