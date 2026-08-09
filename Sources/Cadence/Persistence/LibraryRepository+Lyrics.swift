import Foundation
import SwiftData

struct ManagedLyricMetadata: Equatable, Sendable {
    let trackID: UUID
    let relativePath: String
    let textEncoding: String
    let parsingStatus: StoredLyricParsingStatus
    let timingStatus: LyricTimingStatus
    let contentHash: String
    let modifiedAt: Date
}

enum ManagedLyricMutation: Equatable, Sendable {
    case upsert(
        relativePath: String,
        contentHash: String,
        timingStatus: LyricTimingStatus,
        modifiedAt: Date
    )
    case remove
}

enum ManagedLyricRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case trackNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case let .trackNotFound(trackID):
            "The track \(trackID.uuidString) is no longer in the library."
        }
    }
}

extension LibraryRepository {
    func lyricTrackDuration(
        trackID: UUID
    ) throws -> TimeInterval {
        let predicate = #Predicate<TrackRecord> { track in
            track.id == trackID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let track = try modelContext.fetch(descriptor).first else {
            throw ManagedLyricRepositoryError.trackNotFound(trackID)
        }
        return track.duration
    }

    func lyricMetadata(
        trackID: UUID
    ) throws -> ManagedLyricMetadata? {
        try lyricRecord(trackID: trackID).map {
            ManagedLyricMetadata(
                trackID: $0.trackID,
                relativePath: $0.relativePath,
                textEncoding: $0.textEncoding,
                parsingStatus: $0.parsingStatus,
                timingStatus: $0.timingStatus,
                contentHash: $0.contentHash,
                modifiedAt: $0.modifiedAt
            )
        }
    }

    func allLyricMetadata() throws -> [ManagedLyricMetadata] {
        try modelContext.fetch(
            FetchDescriptor<LyricRecord>()
        ).map(lyricMetadata)
    }

    func applyLyricMutation(
        trackID: UUID,
        mutation: ManagedLyricMutation
    ) throws {
        let predicate = #Predicate<TrackRecord> { track in
            track.id == trackID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let track = try modelContext.fetch(descriptor).first else {
            throw ManagedLyricRepositoryError.trackNotFound(trackID)
        }

        let existing = try lyricRecord(trackID: trackID)
        switch mutation {
        case let .upsert(
            relativePath,
            contentHash,
            timingStatus,
            modifiedAt
        ):
            if let existing {
                existing.relativePath = relativePath
                existing.textEncoding = "UTF-8"
                existing.parsingStatus = .valid
                existing.timingStatus = timingStatus
                existing.contentHash = contentHash
                existing.modifiedAt = modifiedAt
                existing.track = track
            } else {
                modelContext.insert(
                    LyricRecord(
                        relativePath: relativePath,
                        textEncoding: "UTF-8",
                        parsingStatus: .valid,
                        contentHash: contentHash,
                        timingStatus: timingStatus,
                        modifiedAt: modifiedAt,
                        track: track
                    )
                )
            }
        case .remove:
            if let existing {
                modelContext.delete(existing)
            }
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func lyricRecord(
        trackID: UUID
    ) throws -> LyricRecord? {
        let predicate = #Predicate<LyricRecord> { lyric in
            lyric.trackID == trackID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func lyricMetadata(
        _ record: LyricRecord
    ) -> ManagedLyricMetadata {
        ManagedLyricMetadata(
            trackID: record.trackID,
            relativePath: record.relativePath,
            textEncoding: record.textEncoding,
            parsingStatus: record.parsingStatus,
            timingStatus: record.timingStatus,
            contentHash: record.contentHash,
            modifiedAt: record.modifiedAt
        )
    }
}
