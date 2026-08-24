import Foundation

struct ManagedMetadataRepairFailure: Equatable, Sendable {
    let trackID: UUID
    let errorDescription: String
}

struct ManagedMetadataRepairResult: Equatable, Sendable {
    let repairedCount: Int
    let failures: [ManagedMetadataRepairFailure]

    var failedTrackIDs: Set<UUID> {
        Set(failures.map(\.trackID))
    }
}

struct ManagedMetadataRepairService: Sendable {
    let location: ManagedLibraryLocation
    let repository: LibraryRepository
    let reader: MetadataReader

    init(
        location: ManagedLibraryLocation,
        repository: LibraryRepository,
        reader: MetadataReader = MetadataReader()
    ) {
        self.location = location
        self.repository = repository
        self.reader = reader
    }

    func repairAll() async throws -> ManagedMetadataRepairResult {
        var cursor: String?
        var repairedCount = 0
        var failures: [ManagedMetadataRepairFailure] = []

        repeat {
            let page = try await repository.metadataRepairCandidates(
                after: cursor
            )
            let inspection = try await inspect(page.items)
            repairedCount += try await repository.applyMetadataRepairs(
                inspection.repairs
            )
            failures.append(contentsOf: inspection.failures)
            cursor = page.nextCursor
        } while cursor != nil

        return ManagedMetadataRepairResult(
            repairedCount: repairedCount,
            failures: failures
        )
    }

    private func inspect(
        _ candidates: [ManagedMetadataRepairCandidate]
    ) async throws -> ManagedMetadataInspection {
        var repairs: [ManagedMetadataRepair] = []
        var failures: [ManagedMetadataRepairFailure] = []

        for startIndex in stride(
            from: 0,
            to: candidates.count,
            by: 4
        ) {
            let endIndex = min(startIndex + 4, candidates.count)
            let batch = candidates[startIndex ..< endIndex]
            try await withThrowingTaskGroup(
                of: IndexedMetadataInspectionResult.self
            ) { group in
                for (offset, candidate) in batch.enumerated() {
                    group.addTask {
                        try await IndexedMetadataInspectionResult(
                            index: startIndex + offset,
                            result: inspectResult(candidate)
                        )
                    }
                }
                var results: [IndexedMetadataInspectionResult] = []
                for try await result in group {
                    results.append(result)
                }
                for result in results.sorted(by: { $0.index < $1.index }) {
                    switch result.result {
                    case let .repair(repair):
                        repairs.append(repair)
                    case let .failure(failure):
                        failures.append(failure)
                    }
                }
            }
        }

        return ManagedMetadataInspection(
            repairs: repairs,
            failures: failures
        )
    }

    private func inspectResult(
        _ candidate: ManagedMetadataRepairCandidate
    ) async throws -> MetadataInspectionResult {
        do {
            return try await .repair(inspect(candidate))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failure(
                ManagedMetadataRepairFailure(
                    trackID: candidate.id,
                    errorDescription: error.localizedDescription
                )
            )
        }
    }

    private func inspect(
        _ candidate: ManagedMetadataRepairCandidate
    ) async throws -> ManagedMetadataRepair {
        let url = try location.resolve(
            relativePath: candidate.relativeMediaPath,
            directoryHint: .notDirectory
        )
        let scanned = try await reader.read(url: url)
        let metadata = ManagedImportManifest.Metadata(scanned)
        let sourceMetadata = if let snapshot = scanned.sourceMetadata {
            try JSONEncoder().encode(snapshot)
        } else {
            try JSONEncoder().encode(metadata)
        }
        return ManagedMetadataRepair(
            trackID: candidate.id,
            metadata: metadata,
            sourceMetadata: sourceMetadata
        )
    }
}

private struct ManagedMetadataInspection: Sendable {
    let repairs: [ManagedMetadataRepair]
    let failures: [ManagedMetadataRepairFailure]
}

private struct IndexedMetadataInspectionResult: Sendable {
    let index: Int
    let result: MetadataInspectionResult
}

private enum MetadataInspectionResult: Sendable {
    case repair(ManagedMetadataRepair)
    case failure(ManagedMetadataRepairFailure)
}
