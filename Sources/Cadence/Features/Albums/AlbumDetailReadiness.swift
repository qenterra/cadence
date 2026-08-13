import SwiftUI

final class AlbumDetailReadinessObserver: Equatable, @unchecked Sendable {
    private let notifyClosure: @MainActor @Sendable (UUID) -> Void

    init(notify: @escaping @MainActor @Sendable (UUID) -> Void) {
        notifyClosure = notify
    }

    @MainActor
    func notify(_ albumID: UUID) {
        notifyClosure(albumID)
    }

    static func == (
        lhs: AlbumDetailReadinessObserver,
        rhs: AlbumDetailReadinessObserver
    ) -> Bool {
        lhs === rhs
    }
}

extension EnvironmentValues {
    @Entry var albumDetailReadinessObserver: AlbumDetailReadinessObserver?
}
