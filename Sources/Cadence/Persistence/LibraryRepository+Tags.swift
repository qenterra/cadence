import Foundation
import SwiftData

enum ProductionTagAssignmentSource: String, Sendable {
    case direct
    case inherited
}

struct ProductionTrackTagState: Identifiable, Sendable {
    let tag: LibraryTagProjection
    let source: ProductionTagAssignmentSource

    var id: UUID {
        tag.id
    }
}

enum ProductionTagEditError: Error, LocalizedError, Sendable {
    case invalidPath
    case missingTag
    case missingTrack
    case missingTracks

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            "Enter a tag such as mood/sad or childhood."
        case .missingTag:
            "The tag no longer exists."
        case .missingTrack:
            "The track is no longer in the library."
        case .missingTracks:
            "One or more selected tracks are no longer in the library."
        }
    }
}

extension LibraryRepository {
    func tags(
        albumID: UUID
    ) throws -> [LibraryTagProjection] {
        let targetKind = TagTargetKind.album.rawValue
        let predicate = #Predicate<TagAssignmentRecord> {
            $0.targetID == albumID
                && $0.targetKindRawValue == targetKind
        }
        let tagIDs = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        ).map(\.tagID)
        return try tagRecords(ids: tagIDs)
            .map(LibraryProjectionFactory.tag)
    }

    func tagStates(
        trackID: UUID
    ) throws -> [ProductionTrackTagState] {
        guard let track = try trackRecordForTagging(id: trackID) else {
            throw ProductionTagEditError.missingTrack
        }
        let assignmentIDs = try assignmentTagIDs(
            trackID: trackID,
            albumID: track.album?.id
        )
        let excludedIDs = try excludedTagIDs(trackID: trackID)
        let effectiveIDs = assignmentIDs.direct.union(
            assignmentIDs.inherited.subtracting(excludedIDs)
        )
        guard !effectiveIDs.isEmpty else {
            return []
        }
        return try tagRecords(ids: Array(effectiveIDs)).map { record in
            ProductionTrackTagState(
                tag: LibraryProjectionFactory.tag(record),
                source: assignmentIDs.direct.contains(record.id)
                    ? .direct
                    : .inherited
            )
        }
    }

    func setTag(
        _ tagID: UUID,
        assigned: Bool,
        trackID: UUID
    ) throws {
        guard try trackRecordForTagging(id: trackID) != nil else {
            throw ProductionTagEditError.missingTrack
        }
        guard try tagRecord(id: tagID) != nil else {
            throw ProductionTagEditError.missingTag
        }

        let direct = try directAssignment(tagID: tagID, trackID: trackID)
        let inherited = try inheritedAssignment(
            tagID: tagID,
            trackID: trackID
        )
        let exclusion = try exclusion(tagID: tagID, trackID: trackID)

        if assigned {
            if let exclusion {
                modelContext.delete(exclusion)
            } else if direct == nil, !inherited {
                modelContext.insert(
                    TagAssignmentRecord(
                        targetKind: .track,
                        targetID: trackID,
                        tagID: tagID
                    )
                )
            }
        } else {
            if let direct {
                modelContext.delete(direct)
            }
            if inherited, exclusion == nil {
                modelContext.insert(
                    TagExclusionRecord(
                        trackID: trackID,
                        tagID: tagID
                    )
                )
            }
        }
        try modelContext.save()
    }

    @discardableResult
    func createTagAndAssign(
        displayPath: String,
        trackID: UUID
    ) throws -> UUID {
        guard try trackRecordForTagging(id: trackID) != nil else {
            throw ProductionTagEditError.missingTrack
        }
        let tagID = try createTag(displayPath: displayPath)
        try setTag(tagID, assigned: true, trackID: trackID)
        return tagID
    }

    func assignTag(
        _ tagID: UUID,
        albumID: UUID
    ) throws {
        let albumPredicate = #Predicate<AlbumRecord> {
            $0.id == albumID
        }
        var albumDescriptor = FetchDescriptor(
            predicate: albumPredicate
        )
        albumDescriptor.fetchLimit = 1
        guard try modelContext.fetch(albumDescriptor).first != nil else {
            return
        }
        guard try tagRecord(id: tagID) != nil else {
            throw ProductionTagEditError.missingTag
        }
        let targetKind = TagTargetKind.album.rawValue
        let predicate = #Predicate<TagAssignmentRecord> {
            $0.tagID == tagID
                && $0.targetID == albumID
                && $0.targetKindRawValue == targetKind
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        guard try modelContext.fetch(descriptor).isEmpty else {
            return
        }
        modelContext.insert(
            TagAssignmentRecord(
                targetKind: .album,
                targetID: albumID,
                tagID: tagID
            )
        )
        try modelContext.save()
    }
}

private extension LibraryRepository {
    func assignmentTagIDs(
        trackID: UUID,
        albumID: UUID?
    ) throws -> (direct: Set<UUID>, inherited: Set<UUID>) {
        let targetIDs = [trackID, albumID].compactMap(\.self)
        let predicate = #Predicate<TagAssignmentRecord> {
            targetIDs.contains($0.targetID)
        }
        let assignments = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
        let direct = assignments.filter {
            $0.targetKind == .track && $0.targetID == trackID
        }
        let inherited = assignments.filter {
            $0.targetKind == .album && $0.targetID == albumID
        }
        return (
            Set(direct.map(\.tagID)),
            Set(inherited.map(\.tagID))
        )
    }

    func excludedTagIDs(trackID: UUID) throws -> Set<UUID> {
        let predicate = #Predicate<TagExclusionRecord> {
            $0.trackID == trackID
        }
        return try Set(
            modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            )
            .map(\.tagID)
        )
    }

    func tagRecords(
        ids: [UUID]
    ) throws -> [TagRecord] {
        var records: [TagRecord] = []
        for idChunk in tagPredicateChunks(ids) {
            let predicate = #Predicate<TagRecord> {
                idChunk.contains($0.id)
            }
            try records.append(
                contentsOf: modelContext.fetch(
                    FetchDescriptor(predicate: predicate)
                )
            )
        }
        return records.sorted {
            $0.normalizedPath < $1.normalizedPath
        }
    }

    func trackRecordForTagging(id: UUID) throws -> TrackRecord? {
        let predicate = #Predicate<TrackRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func tagRecord(id: UUID) throws -> TagRecord? {
        let predicate = #Predicate<TagRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func directAssignment(
        tagID: UUID,
        trackID: UUID
    ) throws -> TagAssignmentRecord? {
        let targetKind = TagTargetKind.track.rawValue
        let predicate = #Predicate<TagAssignmentRecord> {
            $0.tagID == tagID
                && $0.targetID == trackID
                && $0.targetKindRawValue == targetKind
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func inheritedAssignment(
        tagID: UUID,
        trackID: UUID
    ) throws -> Bool {
        guard let albumID = try trackRecordForTagging(id: trackID)?.album?.id else {
            return false
        }
        let targetKind = TagTargetKind.album.rawValue
        let predicate = #Predicate<TagAssignmentRecord> {
            $0.tagID == tagID
                && $0.targetID == albumID
                && $0.targetKindRawValue == targetKind
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    func exclusion(
        tagID: UUID,
        trackID: UUID
    ) throws -> TagExclusionRecord? {
        let predicate = #Predicate<TagExclusionRecord> {
            $0.tagID == tagID && $0.trackID == trackID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
