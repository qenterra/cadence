import Foundation
import SwiftData

extension LibraryRepository {
    @discardableResult
    func pruneListeningHistory(olderThan cutoff: Date) throws -> Int {
        let predicate = #Predicate<TrackRecord> { track in
            track.lastPlayedAt != nil
        }
        let records = try modelContext.fetch(
            FetchDescriptor<TrackRecord>(predicate: predicate)
        ).filter { record in
            record.lastPlayedAt.map { $0 < cutoff } == true
        }
        guard !records.isEmpty else {
            return 0
        }
        for record in records {
            record.lastPlayedAt = nil
        }
        try modelContext.save()
        return records.count
    }
}

extension LibraryStore {
    @discardableResult
    func pruneListeningHistory(olderThan cutoff: Date) async throws -> Int {
        let context = captureLibraryContext()
        let repository = try requireRepository()
        let clearedCount = try await repository.pruneListeningHistory(
            olderThan: cutoff
        )
        guard isCurrentLibraryContext(context) else {
            return clearedCount
        }
        if clearedCount > 0 {
            await refreshAfterSemanticTrackMutation(context: context)
        }
        return clearedCount
    }

    @discardableResult
    func emptyExpiredTrash(
        olderThan cutoff: Date,
        location: ManagedLibraryLocation?
    ) async throws -> Int {
        guard let location else {
            throw LibraryTrashError.unavailableLibrary
        }
        let context = captureLibraryContext()
        let repository = try requireRepository()
        do {
            let removedCount = try await repository.emptyExpiredTrash(
                olderThan: cutoff,
                location: location
            )
            guard isCurrentLibraryContext(context) else {
                return removedCount
            }
            if removedCount > 0 {
                await loadInitialLibrary()
            }
            return removedCount
        } catch let error as LibraryTrashTransactionError
            where error.phase == .cleanup {
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            await loadInitialLibrary()
            throw error
        }
    }
}
