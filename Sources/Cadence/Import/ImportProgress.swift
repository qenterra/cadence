import Foundation

enum ImportProgressPhase: String, Equatable, Sendable {
    case discovering
    case scanning
    case copying
    case verifying
    case saving

    var title: String {
        switch self {
        case .discovering:
            String(localized: "Discovering Files")
        case .scanning:
            String(localized: "Scanning Music")
        case .copying:
            String(localized: "Copying Music")
        case .verifying:
            String(localized: "Verifying Copies")
        case .saving:
            String(localized: "Saving Library")
        }
    }
}

struct ImportProgress: Equatable, Sendable {
    let phase: ImportProgressPhase
    let completedCount: Int
    let totalCount: Int
    let copiedByteCount: Int64

    init(
        phase: ImportProgressPhase,
        completedCount: Int,
        totalCount: Int,
        copiedByteCount: Int64 = 0
    ) {
        self.phase = phase
        self.completedCount = max(completedCount, 0)
        self.totalCount = max(totalCount, 0)
        self.copiedByteCount = max(copiedByteCount, 0)
    }

    static let empty = ImportProgress(
        phase: .discovering,
        completedCount: 0,
        totalCount: 0
    )

    var fractionCompleted: Double {
        guard totalCount > 0 else {
            return 0
        }
        return min(Double(completedCount) / Double(totalCount), 1)
    }

    var primaryLabel: String {
        guard totalCount > 0 else {
            return phase.title
        }
        return String(
            localized: "\(min(completedCount, totalCount)) of \(totalCount)"
        )
    }

    var isCommitting: Bool {
        phase == .saving
    }
}

typealias ImportInspectionProgress = ImportProgress
typealias ManagedImportProgress = ImportProgress

struct ImportProgressPublicationPolicy {
    private let minimumInterval: Duration
    private var lastPublishedAt: ContinuousClock.Instant?
    private var lastPublishedPhase: ImportProgressPhase?

    init(
        minimumInterval: Duration = .milliseconds(100)
    ) {
        self.minimumInterval = minimumInterval
    }

    mutating func shouldPublish(
        _ progress: ImportProgress,
        now: ContinuousClock.Instant = .now
    ) -> Bool {
        let phaseChanged = lastPublishedPhase != progress.phase
        let isComplete = progress.totalCount > 0
            && progress.completedCount >= progress.totalCount
        let intervalElapsed = lastPublishedAt.map {
            $0.duration(to: now) >= minimumInterval
        } ?? true
        guard phaseChanged || isComplete || intervalElapsed else {
            return false
        }
        lastPublishedAt = now
        lastPublishedPhase = progress.phase
        return true
    }
}
