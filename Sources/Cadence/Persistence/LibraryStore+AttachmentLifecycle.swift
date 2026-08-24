import Foundation

enum LibraryAttachmentPhase: Equatable, Sendable {
    case detached
    case active
    case retiring
    case retirementFailed
}

enum LibraryAttachmentLifecycleError: Error, LocalizedError, Sendable {
    case transitionInProgress

    var errorDescription: String? {
        switch self {
        case .transitionInProgress:
            String(localized: "A managed library replacement is already in progress.")
        }
    }
}

struct LibraryAttachmentTaskEntry {
    let token: UUID
    let epoch: UInt64
    let cancel: @MainActor () -> Void
    let join: @MainActor () async -> Void
}

extension LibraryStore {
    func startAttachmentTask<Value: Sendable>(
        context: LibraryStoreContext,
        operation: @escaping @MainActor @Sendable () async throws -> Value
    ) -> Task<Value, Error>? {
        guard
            attachmentPhase == .active,
            isCurrentLibraryContext(context)
        else {
            return nil
        }
        let token = UUID()
        let epoch = context.epoch
        let task = Task<Value, Error> { @MainActor [weak self] in
            defer {
                self?.finishAttachmentTask(token: token, epoch: epoch)
            }
            guard
                let self,
                isCurrentLibraryContext(context)
            else {
                throw CancellationError()
            }
            return try await operation()
        }
        attachmentTasks[token] = LibraryAttachmentTaskEntry(
            token: token,
            epoch: epoch,
            cancel: { task.cancel() },
            join: { _ = try? await task.value }
        )
        return task
    }

    func retireCurrentAttachment() async throws {
        guard attachmentPhase != .retiring else {
            throw LibraryAttachmentLifecycleError.transitionInProgress
        }

        advanceLibraryEpoch()
        attachmentPhase = .retiring

        let ownedTasks = Array(attachmentTasks.values)
        attachmentTasks.removeAll()
        let artworkMetadataTasks = artworkMetadataLoads.values.map(\.task)
        artworkMetadataLoads.removeAll()
        let artworkDataTasks = artworkDataLoads.values.map(\.task)
        artworkDataLoads.removeAll()
        let oldIndexer = lyricsSearchIndexer

        ownedTasks.forEach { $0.cancel() }
        artworkMetadataTasks.forEach { $0.cancel() }
        artworkDataTasks.forEach { $0.cancel() }
        retireArtworkLookupResults()

        for entry in ownedTasks {
            await entry.join()
        }
        for task in artworkMetadataTasks {
            _ = try? await task.value
        }
        for task in artworkDataTasks {
            _ = try? await task.value
        }

        do {
            try await oldIndexer?.close()
        } catch {
            attachmentPhase = .retirementFailed
            throw error
        }
    }

    func retireArtworkLookupResults() {
        artworkMetadataResults.removeAll()
        artworkAssetCache = ArtworkAssetCache()
        artworkLookupGenerations.removeAll()
    }
}

private extension LibraryStore {
    func finishAttachmentTask(token: UUID, epoch: UInt64) {
        guard
            let entry = attachmentTasks[token],
            entry.token == token,
            entry.epoch == epoch
        else {
            return
        }
        attachmentTasks[token] = nil
    }
}
