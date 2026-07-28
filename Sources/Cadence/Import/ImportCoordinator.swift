import Foundation
import Observation

enum ImportCoordinatorState: Equatable, Sendable {
    case empty
    case scanning(ImportInspectionProgress)
    case review([ImportInspectionCandidate])
    case importing(ManagedImportProgress)
    case complete(ManagedImportCompletion)
    case importFailed(String)
    case failed(String)
}

@MainActor
@Observable
final class ImportCoordinator {
    private let service: ImportInspectionService
    private let importer: ManagedLibraryImporter?

    @ObservationIgnored
    private var scanTask: Task<Void, Never>?

    @ObservationIgnored
    private var sourceAccess: SecurityScopedSourceAccess?

    @ObservationIgnored
    private var activeScanID: UUID?

    @ObservationIgnored
    private var reviewedCandidates: [ImportInspectionCandidate] = []

    @ObservationIgnored
    private var sourceDisplayName = "Selected Music"

    var state: ImportCoordinatorState = .empty {
        didSet {
            onStateChange?(state)
        }
    }

    @ObservationIgnored
    var onStateChange: (@MainActor (ImportCoordinatorState) -> Void)?

    init(
        service: ImportInspectionService,
        importer: ManagedLibraryImporter? = nil
    ) {
        self.service = service
        self.importer = importer
    }

    func start(source: ImportSource) {
        cancel()
        let scanID = UUID()
        activeScanID = scanID
        sourceAccess = SecurityScopedSourceAccess(urls: source.urls)
        sourceDisplayName = Self.displayName(for: source)
        reviewedCandidates = []
        state = .scanning(.empty)

        let service = service
        scanTask = Task { [weak self] in
            guard let coordinator = self else {
                return
            }
            do {
                let candidates = try await service.inspect(
                    source: source
                ) { progress in
                    await coordinator.report(
                        progress,
                        scanID: scanID
                    )
                }
                try Task.checkCancellation()
                guard coordinator.activeScanID == scanID else {
                    return
                }
                coordinator.reviewedCandidates = candidates
                coordinator.state = .review(candidates)
            } catch is CancellationError {
                return
            } catch {
                guard coordinator.activeScanID == scanID else {
                    return
                }
                coordinator.releaseSourceAccess()
                coordinator.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        let isCommitting: Bool = if case let .importing(progress) = state {
            progress.isCommitting
        } else {
            false
        }
        if isCommitting {
            return
        }
        if case .importing = state {
            scanTask?.cancel()
            scanTask = nil
            state = .review(reviewedCandidates)
            return
        }
        scanTask?.cancel()
        scanTask = nil
        activeScanID = nil
        releaseSourceAccess()
        state = .empty
    }

    func beginImport(
        includedIDs: Set<UUID>
    ) {
        guard
            case .review = state,
            let importer,
            !includedIDs.isEmpty
        else {
            return
        }
        let candidates = reviewedCandidates
        let sourceDisplayName = sourceDisplayName
        state = .importing(
            ManagedImportProgress(
                completedCount: 0,
                totalCount: includedIDs.count,
                copiedByteCount: 0,
                currentFilename: nil,
                isCommitting: false
            )
        )
        scanTask = Task { [weak self] in
            guard let coordinator = self else {
                return
            }
            do {
                let completion = try await importer.importCandidates(
                    candidates,
                    includedIDs: includedIDs,
                    sourceDisplayName: sourceDisplayName
                ) { progress in
                    await coordinator.reportImport(progress)
                }
                coordinator.releaseSourceAccess()
                coordinator.state = .complete(completion)
            } catch is CancellationError {
                coordinator.state = .review(candidates)
            } catch {
                coordinator.state = .importFailed(
                    error.localizedDescription
                )
            }
        }
    }

    private func report(
        _ progress: ImportInspectionProgress,
        scanID: UUID
    ) {
        guard
            activeScanID == scanID,
            scanTask?.isCancelled == false
        else {
            return
        }
        state = .scanning(progress)
    }

    private func reportImport(
        _ progress: ManagedImportProgress
    ) {
        state = .importing(progress)
    }

    private func releaseSourceAccess() {
        sourceAccess?.release()
        sourceAccess = nil
    }

    private static func displayName(
        for source: ImportSource
    ) -> String {
        guard source.urls.count == 1 else {
            return "\(source.urls.count) selected items"
        }
        return source.urls[0].lastPathComponent
    }
}

@MainActor
private final class SecurityScopedSourceAccess {
    private var accessedURLs: [URL]

    init(urls: [URL]) {
        accessedURLs = Array(Set(urls.map(\.standardizedFileURL)))
            .filter { $0.startAccessingSecurityScopedResource() }
    }

    func release() {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()
    }

    deinit {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
