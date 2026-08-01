import Foundation
import SwiftData

extension LibraryRepository {
    func playbackQueueTracks(
        ids: [UUID]
    ) throws -> [PlaybackQueueTrackProjection] {
        guard !ids.isEmpty else {
            return []
        }

        var seenIDs: Set<UUID> = []
        let uniqueIDs = ids.filter { seenIDs.insert($0).inserted }
        var recordsByID: [UUID: TrackRecord] = [:]

        for startIndex in stride(
            from: uniqueIDs.startIndex,
            to: uniqueIDs.endIndex,
            by: 100
        ) {
            let endIndex = min(startIndex + 100, uniqueIDs.endIndex)
            let chunk = Array(uniqueIDs[startIndex ..< endIndex])
            let predicate = #Predicate<TrackRecord> { track in
                chunk.contains(track.id)
            }
            let records = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            )
            for record in records {
                recordsByID[record.id] = record
            }
        }

        return ids.map { id in
            PlaybackQueueTrackProjection(
                id: id,
                state: recordsByID[id].map {
                    .available(LibraryProjectionFactory.track($0))
                } ?? .unavailable
            )
        }
    }
}
