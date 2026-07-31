import Foundation
import SwiftData

extension LibraryRepository {
    func tracksForTagPicker() throws -> [LibraryTrackProjection] {
        try modelContext.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [
                    SortDescriptor(\.normalizedTitle),
                    SortDescriptor(\.sortIdentity),
                ]
            )
        ).map(LibraryProjectionFactory.track)
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

        let trackPredicate = #Predicate<TrackRecord> {
            requestedIDs.contains($0.id)
        }
        let liveTrackIDs = try Set(
            modelContext.fetch(
                FetchDescriptor(predicate: trackPredicate)
            )
            .map(\.id)
        )
        guard liveTrackIDs.count == requestedIDs.count else {
            throw ProductionTagEditError.missingTracks
        }

        let targetKind = TagTargetKind.track.rawValue
        let assignmentPredicate = #Predicate<TagAssignmentRecord> {
            $0.tagID == tagID
                && requestedIDs.contains($0.targetID)
                && $0.targetKindRawValue == targetKind
        }
        let existingIDs = try Set(
            modelContext.fetch(
                FetchDescriptor(predicate: assignmentPredicate)
            )
            .map(\.targetID)
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
}
