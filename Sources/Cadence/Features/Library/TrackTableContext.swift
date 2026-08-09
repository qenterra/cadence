import Foundation

enum TrackTableContext: Hashable, Codable, Sendable {
    case library
    case album(UUID)
    case artist(UUID)
    case smartCollection(UUID)
    case playlist(UUID)
    case search(String)
    case tag(UUID)
}
