import Foundation

enum RemoteProviderError: Error, Equatable, LocalizedError, Sendable {
    case authenticationRequired
    case conflict
    case integrityMismatch
    case interrupted
    case invalidManifest(String)
    case invalidRange
    case objectNotFound(RemoteObjectID)
    case rangeNotSupported
    case serviceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            "Sign in to the remote library again."
        case .conflict:
            "The remote library changed on another device. Refresh before saving."
        case .integrityMismatch:
            "The downloaded file did not match its verified content hash."
        case .interrupted:
            "The remote transfer was interrupted."
        case let .invalidManifest(reason):
            "The remote library manifest is invalid: \(reason)"
        case .invalidRange:
            "The requested byte range is invalid."
        case let .objectNotFound(object):
            "The remote object \(object.rawValue) is unavailable."
        case .rangeNotSupported:
            "This remote server does not support byte-range downloads."
        case let .serviceUnavailable(reason):
            "The remote library is unavailable: \(reason)"
        }
    }
}
