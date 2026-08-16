import Foundation

enum CadenceModePreferences {
    static let staysActiveKey = "cadenceMode.staysActive"
}

enum CadenceModeTimeoutPolicy: Equatable, Sendable {
    case inactivity(TimeInterval)
    case persistent

    func deadline(after time: TimeInterval) -> TimeInterval? {
        switch self {
        case let .inactivity(duration):
            time + duration
        case .persistent:
            nil
        }
    }
}
