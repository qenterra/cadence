import Foundation

enum RemoteCacheError: Error, LocalizedError {
    case directoryPreparationFailed(URL, Error)
    case corruptIndex(URL, Error?)
    case indexPersistenceFailed(URL, Error)
    case objectInspectionFailed(URL, Error)
    case objectRemovalFailed(URL, Error)
    case promotionRollbackFailed(URL, Error, Error)
    case stagingCleanupFailed(URL, Error, Error?)

    var errorDescription: String? {
        switch self {
        case let .directoryPreparationFailed(url, _):
            "The remote cache directory could not be prepared at \(url.path)."
        case let .corruptIndex(url, _):
            "The remote cache index is unreadable at \(url.path)."
        case let .indexPersistenceFailed(url, _):
            "The remote cache index could not be saved at \(url.path)."
        case let .objectInspectionFailed(url, _):
            "A cached object could not be inspected at \(url.path)."
        case let .objectRemovalFailed(url, _):
            "A cached object could not be removed at \(url.path)."
        case let .promotionRollbackFailed(url, _, _):
            "A failed cache promotion could not be rolled back at \(url.path)."
        case let .stagingCleanupFailed(url, _, _):
            "The remote cache staging area could not be reconciled at \(url.path)."
        }
    }
}
