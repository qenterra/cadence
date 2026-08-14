import Foundation

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

    func repairAll() async throws -> Int {
        var cursor: String?
        var repairedCount = 0

        repeat {
            let page = try await repository.metadataRepairCandidates(
                after: cursor
            )
            let repairs = try await inspect(page.items)
            repairedCount += try await repository.applyMetadataRepairs(
                repairs
            )
            cursor = page.nextCursor
        } while cursor != nil

        return repairedCount
    }

    private func inspect(
        _ candidates: [ManagedMetadataRepairCandidate]
    ) async throws -> [ManagedMetadataRepair] {
        var repairs: [ManagedMetadataRepair] = []

        for startIndex in stride(
            from: 0,
            to: candidates.count,
            by: 4
        ) {
            let endIndex = min(startIndex + 4, candidates.count)
            let batch = candidates[startIndex ..< endIndex]
            try await withThrowingTaskGroup(
                of: ManagedMetadataRepair.self
            ) { group in
                for candidate in batch {
                    group.addTask {
                        try await inspect(candidate)
                    }
                }
                for try await repair in group {
                    repairs.append(repair)
                }
            }
        }

        return repairs
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
