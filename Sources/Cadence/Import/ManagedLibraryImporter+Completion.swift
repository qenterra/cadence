import Foundation

extension ManagedLibraryImporter {
    func executePreparedImport(
        manifest initialManifest: ManagedImportManifest,
        repository: LibraryRepository,
        candidates: [ImportInspectionCandidate],
        selected: [ImportInspectionCandidate],
        progress: @escaping @Sendable (
            ManagedImportProgress
        ) async -> Void
    ) async throws -> ManagedImportCompletion {
        var manifest = initialManifest
        do {
            let copiedEntries = try await copyToStaging(
                manifest: manifest,
                progress: progress
            )
            manifest = try manifest.advancing(
                to: .copied,
                entries: copiedEntries
            )
            try manifestStore.save(manifest)
            try failureInjector(.afterCopied)
            await reportCommitting(copiedEntries, progress: progress)

            try commitFiles(manifest)
            manifest = try manifest.advancing(to: .filesCommitted)
            try manifestStore.save(manifest)
            try failureInjector(.afterFilesCommitted)

            let storeResult = try await repository.commitImport(manifest)
            manifest = try manifest.advancing(to: .storeCommitted)
            try manifestStore.save(manifest)
            try failureInjector(.afterStoreCommitted)

            try await repository.completeImport(importID: manifest.importID)
            manifest = try manifest.advancing(to: .complete)
            try manifestStore.save(manifest)
            try manifestStore.remove(importID: manifest.importID)
            return completion(
                importID: manifest.importID,
                candidates: candidates,
                selected: selected,
                storeResult: storeResult
            )
        } catch is ManagedImportInjectedFailure {
            throw ManagedImportInjectedFailure()
        } catch {
            return try await recoverOrRethrow(
                error,
                manifest: manifest,
                candidates: candidates,
                selected: selected
            )
        }
    }

    func completion(
        importID: UUID,
        candidates: [ImportInspectionCandidate],
        selected: [ImportInspectionCandidate],
        storeResult: ManagedImportStoreResult
    ) -> ManagedImportCompletion {
        ManagedImportCompletion(
            importID: importID,
            importedTrackIDs: storeResult.importedTrackIDs,
            lyricsLinked: storeResult.lyricsLinked,
            exactDuplicatesSkipped: candidates.count {
                $0.duplicateDisposition == .exactDuplicate
            },
            filesNotImported: candidates.count - selected.count,
            importedByteCount: storeResult.selectedByteCount
        )
    }

    func recoveredCompletion(
        manifest: ManagedImportManifest,
        candidates: [ImportInspectionCandidate],
        selected: [ImportInspectionCandidate]
    ) -> ManagedImportCompletion {
        let committedEntries = manifest.entries.filter {
            $0.state == .copied
        }
        return ManagedImportCompletion(
            importID: manifest.importID,
            importedTrackIDs: committedEntries.map(\.trackID),
            lyricsLinked: committedEntries.count {
                $0.lyric?.contentHash != nil
            },
            exactDuplicatesSkipped: candidates.count {
                $0.duplicateDisposition == .exactDuplicate
            },
            filesNotImported: candidates.count - selected.count,
            importedByteCount: committedEntries.reduce(0) {
                $0 + $1.sizeInBytes
            }
        )
    }

    private func reportCommitting(
        _ entries: [ManagedImportManifest.Entry],
        progress: @escaping @Sendable (
            ManagedImportProgress
        ) async -> Void
    ) async {
        await progress(
            ManagedImportProgress(
                phase: .saving,
                completedCount: entries.count,
                totalCount: entries.count
            )
        )
    }

    private func recoverOrRethrow(
        _ error: any Error,
        manifest: ManagedImportManifest,
        candidates: [ImportInspectionCandidate],
        selected: [ImportInspectionCandidate]
    ) async throws -> ManagedImportCompletion {
        let recovery = ManagedLibraryImportRecovery(
            destination: destination
        )
        let result = try? await recovery.recover()
        if result?.recoveredImportIDs.contains(manifest.importID) == true {
            return recoveredCompletion(
                manifest: manifest,
                candidates: candidates,
                selected: selected
            )
        }
        throw error
    }
}
