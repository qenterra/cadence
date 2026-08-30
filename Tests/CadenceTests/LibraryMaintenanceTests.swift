@testable import Cadence
import Foundation
import SwiftData
import Testing

struct LibraryMaintenanceTests {
    @Test("Automatic cleanup removes only completed Trash operations older than the cutoff")
    func emptyExpiredTrash() async throws {
        let fixture = try TrashFixture()
        defer { fixture.remove() }
        let repository = LibraryRepository(modelContainer: fixture.container)
        let operationIDs = try await repository.trashTracks(
            targetIDs: Array(fixture.trackIDs.prefix(2)),
            location: fixture.location
        )
        let oldOperationID = try #require(operationIDs.first)
        let freshOperationID = try #require(operationIDs.last)
        let cutoff = Date(timeIntervalSince1970: 10000)

        let context = ModelContext(fixture.container)
        let records = try context.fetch(FetchDescriptor<TrashOperationRecord>())
        records.first { $0.id == oldOperationID }?.completedAt =
            cutoff.addingTimeInterval(-1)
        records.first { $0.id == freshOperationID }?.completedAt = cutoff
        let incompleteID = UUID()
        try context.insert(
            TrashOperationRecord(
                id: incompleteID,
                targetKind: .track,
                targetIDsData: JSONEncoder().encode([UUID]()),
                originalRelativePathsData: JSONEncoder().encode([String]()),
                createdAt: cutoff.addingTimeInterval(-100),
                completedAt: nil
            )
        )
        try context.save()

        let removedCount = try await repository.emptyExpiredTrash(
            olderThan: cutoff,
            location: fixture.location
        )

        #expect(removedCount == 1)
        let remainingIDs = try Set(
            context.fetch(FetchDescriptor<TrashOperationRecord>()).map(\.id)
        )
        #expect(remainingIDs == [freshOperationID, incompleteID])
        #expect(!fixture.operationDirectory(oldOperationID).fileExists)
        #expect(fixture.operationDirectory(freshOperationID).fileExists)
    }
}
