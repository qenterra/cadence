import Foundation

extension LibraryStore {
    func loadNextTags() async {
        guard
            !isLoadingNextTags,
            let tagCursor
        else {
            return
        }

        isLoadingNextTags = true
        let generation = tagGeneration
        defer {
            isLoadingNextTags = false
        }

        do {
            let repository = try requireRepository()
            let page = try await repository.tagsPage(after: tagCursor)
            guard generation == tagGeneration else {
                return
            }
            let existingIDs = Set(tags.map(\.id))
            tags.append(
                contentsOf: page.items.filter {
                    !existingIDs.contains($0.id)
                }
            )
            self.tagCursor = page.nextCursor
        } catch {
            guard generation == tagGeneration else {
                return
            }
            recordOperationFailure(.tagPage, error: error)
        }
    }

    func tracksForTagPicker(
        after cursor: LibraryPageCursor? = nil,
        search: String? = nil
    ) async throws -> LibraryPage<LibraryTrackProjection> {
        let repository = try requireRepository()
        return try await repository.tracksForTagPicker(
            after: cursor,
            search: search
        )
    }

    @discardableResult
    func createTag(
        displayPath: String
    ) async throws -> UUID? {
        let repository = try requireRepository()
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
        let repository = try requireRepository()
        return try await repository.tags(albumID: albumID)
    }

    func tagStates(
        trackID: UUID
    ) async throws -> [ProductionTrackTagState] {
        let repository = try requireRepository()
        return try await repository.tagStates(trackID: trackID)
    }

    func tagStatesReportingFailure(
        trackID: UUID
    ) async -> [ProductionTrackTagState]? {
        do {
            return try await tagStates(trackID: trackID)
        } catch {
            recordOperationFailure(.tagLoad, error: error)
            return nil
        }
    }

    func setTag(
        _ tagID: UUID,
        assigned: Bool,
        trackID: UUID
    ) async throws {
        let repository = try requireRepository()
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
        let repository = try requireRepository()
        return try await repository.directlyAssignedTrackIDs(tagID: tagID)
    }

    func assignTag(
        _ tagID: UUID,
        trackIDs: [UUID]
    ) async throws {
        let repository = try requireRepository()
        try await repository.assignTag(tagID, trackIDs: trackIDs)
        tagRevision &+= 1
        await refreshTags()
    }

    func assignTagReportingFailure(
        _ tagID: UUID,
        trackIDs: [UUID]
    ) async {
        do {
            try await assignTag(tagID, trackIDs: trackIDs)
        } catch {
            recordOperationFailure(.tagMutation, error: error)
        }
    }

    @discardableResult
    func createTagAndAssign(
        displayPath: String,
        trackID: UUID
    ) async throws -> UUID? {
        let repository = try requireRepository()
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
        let repository = try requireRepository()
        try await repository.assignTag(tagID, albumID: albumID)
        tagRevision &+= 1
        await refreshTags()
    }

    func assignTagReportingFailure(
        _ tagID: UUID,
        albumID: UUID
    ) async {
        do {
            try await assignTag(tagID, albumID: albumID)
        } catch {
            recordOperationFailure(.tagMutation, error: error)
        }
    }

    private func refreshTags() async {
        do {
            let repository = try requireRepository()
            let page = try await repository.tagsPage()
            tags = page.items
            tagCursor = page.nextCursor
            tagGeneration &+= 1
        } catch {
            recordOperationFailure(.tagPage, error: error)
        }
    }
}
