import Foundation

extension LibraryStore {
    func tagStates(
        trackID: UUID
    ) async throws -> [ProductionTrackTagState] {
        guard let repository else {
            return []
        }
        return try await repository.tagStates(trackID: trackID)
    }

    func setTag(
        _ tagID: UUID,
        assigned: Bool,
        trackID: UUID
    ) async throws {
        guard let repository else {
            return
        }
        try await repository.setTag(
            tagID,
            assigned: assigned,
            trackID: trackID
        )
        tagRevision &+= 1
        await refreshTags()
    }

    @discardableResult
    func createTagAndAssign(
        displayPath: String,
        trackID: UUID
    ) async throws -> UUID? {
        guard let repository else {
            return nil
        }
        let tagID = try await repository.createTagAndAssign(
            displayPath: displayPath,
            trackID: trackID
        )
        tagRevision &+= 1
        await refreshTags()
        return tagID
    }

    func assignTag(
        _ tagID: UUID,
        albumID: UUID
    ) async throws {
        guard let repository else {
            return
        }
        try await repository.assignTag(tagID, albumID: albumID)
        tagRevision &+= 1
        await refreshTags()
    }

    private func refreshTags() async {
        guard let repository else {
            return
        }
        do {
            tags = try await repository.tagsPage().items
        } catch {
            availability = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
        }
    }
}
