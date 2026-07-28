import Foundation

struct ImportInspectionProgress: Equatable, Sendable {
    let completedCount: Int
    let totalCount: Int
    let currentFilename: String?

    static let empty = ImportInspectionProgress(
        completedCount: 0,
        totalCount: 0,
        currentFilename: nil
    )

    var fractionCompleted: Double {
        guard totalCount > 0 else {
            return 0
        }
        return Double(completedCount) / Double(totalCount)
    }
}

struct ImportDuplicateLookup: Sendable {
    private let operation: @Sendable (
        [ImportDuplicateProbe]
    ) async throws -> ImportDuplicateEvidence

    init(
        operation: @escaping @Sendable (
            [ImportDuplicateProbe]
        ) async throws -> ImportDuplicateEvidence
    ) {
        self.operation = operation
    }

    func evidence(
        for probes: [ImportDuplicateProbe]
    ) async throws -> ImportDuplicateEvidence {
        try await operation(probes)
    }

    static let empty = ImportDuplicateLookup { _ in .empty }

    static func repository(
        _ repository: LibraryRepository
    ) -> ImportDuplicateLookup {
        ImportDuplicateLookup { probes in
            try await repository.importDuplicateEvidence(
                probes: probes
            )
        }
    }
}

struct ImportInspectionService: Sendable {
    static let defaultMaximumConcurrentFiles = 4

    private let scanner: SourceScanner
    private let inspector: any ImportFileInspecting
    private let duplicateLookup: ImportDuplicateLookup
    private let classifier: DuplicateClassifier
    let maximumConcurrentFiles: Int

    init(
        scanner: SourceScanner = SourceScanner(),
        inspector: any ImportFileInspecting = ImportFileInspector(),
        duplicateLookup: ImportDuplicateLookup = .empty,
        classifier: DuplicateClassifier = DuplicateClassifier(),
        maximumConcurrentFiles: Int = defaultMaximumConcurrentFiles
    ) {
        self.scanner = scanner
        self.inspector = inspector
        self.duplicateLookup = duplicateLookup
        self.classifier = classifier
        self.maximumConcurrentFiles = min(
            max(maximumConcurrentFiles, 1),
            Self.defaultMaximumConcurrentFiles
        )
    }

    func inspect(
        source: ImportSource,
        progress: @escaping @Sendable (
            ImportInspectionProgress
        ) async -> Void = { _ in }
    ) async throws -> [ImportInspectionCandidate] {
        let files = try await scanner.scan(source: source)
        let audioFiles = files.filter {
            if case .audio = $0.kind {
                return true
            }
            return false
        }
        await progress(
            ImportInspectionProgress(
                completedCount: 0,
                totalCount: audioFiles.count,
                currentFilename: nil
            )
        )

        let drafts = try await inspect(
            audioFiles: audioFiles,
            allFiles: files,
            progress: progress
        )
        let probes = drafts.compactMap(\.duplicateProbe)
        let evidence = try await duplicateLookup.evidence(for: probes)
        return classifier.classify(drafts, evidence: evidence)
    }

    private func inspect(
        audioFiles: [ScannedSourceFile],
        allFiles: [ScannedSourceFile],
        progress: @escaping @Sendable (
            ImportInspectionProgress
        ) async -> Void
    ) async throws -> [ImportInspectionDraft] {
        guard !audioFiles.isEmpty else {
            return []
        }

        return try await withThrowingTaskGroup(
            of: (Int, ImportInspectionDraft).self,
            returning: [ImportInspectionDraft].self
        ) { group in
            var nextIndex = 0
            var completedCount = 0
            var indexedDrafts: [Int: ImportInspectionDraft] = [:]

            let initialTaskCount = min(
                audioFiles.count,
                maximumConcurrentFiles
            )
            while nextIndex < initialTaskCount {
                addInspectionTask(
                    at: nextIndex,
                    audioFiles: audioFiles,
                    allFiles: allFiles,
                    group: &group
                )
                nextIndex += 1
            }

            while let (index, draft) = try await group.next() {
                try Task.checkCancellation()
                indexedDrafts[index] = draft
                completedCount += 1
                await progress(
                    ImportInspectionProgress(
                        completedCount: completedCount,
                        totalCount: audioFiles.count,
                        currentFilename: draft.sourceFile.url.lastPathComponent
                    )
                )

                if nextIndex < audioFiles.count {
                    addInspectionTask(
                        at: nextIndex,
                        audioFiles: audioFiles,
                        allFiles: allFiles,
                        group: &group
                    )
                    nextIndex += 1
                }
            }

            return audioFiles.indices.compactMap {
                indexedDrafts[$0]
            }
        }
    }

    private func addInspectionTask(
        at index: Int,
        audioFiles: [ScannedSourceFile],
        allFiles: [ScannedSourceFile],
        group: inout ThrowingTaskGroup<
            (Int, ImportInspectionDraft),
            any Error
        >
    ) {
        let inspector = inspector
        group.addTask {
            let draft = try await inspector.inspect(
                audio: audioFiles[index],
                among: allFiles
            )
            return (index, draft)
        }
    }
}
