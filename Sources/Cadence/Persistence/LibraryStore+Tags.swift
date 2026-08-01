import Foundation

extension LibraryStore {
    func tracksForTagPicker(
        after cursor: LibraryPageCursor? = nil,
        search: String? = nil
    ) async throws -> LibraryPage<LibraryTrackProjection> {
        guard let repository else {
            return LibraryPage(items: [], nextCursor: nil)
        }
        return try await repository.tracksForTagPicker(
            after: cursor,
            search: search
        )
    }

    @discardableResult
    func createTag(
        displayPath: String
    ) async throws -> UUID? {
        guard let repository else {
            return nil
        }
        let tagID = try await repository.createTag(
            displayPath: displayPath
        )
        tagRevision &+= 1
        await refreshTags()
        return tagID
    }

    func tags(
        albumID: UUID
    ) async throws -> [LibraryTagProjection] {
        guard let repository else {
            return []
        }
        return try await repository.tags(albumID: albumID)
    }

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

    func directlyAssignedTrackIDs(
        tagID: UUID
    ) async throws -> Set<UUID> {
        guard let repository else {
            return []
        }
        return try await repository.directlyAssignedTrackIDs(tagID: tagID)
    }

    func assignTag(
        _ tagID: UUID,
        trackIDs: [UUID]
    ) async throws {
        guard let repository else {
            return
        }
        try await repository.assignTag(tagID, trackIDs: trackIDs)
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
            let page = try await repository.tagsPage()
            tags = page.items
            tagCursor = page.nextCursor
            tagGeneration &+= 1
        } catch {
            availability = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
        }
    }
}
