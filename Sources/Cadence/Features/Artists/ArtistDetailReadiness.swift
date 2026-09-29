import SwiftUI

final class ArtistDetailReadinessObserver: Equatable, @unchecked Sendable {
    private let notifyClosure: @MainActor @Sendable (UUID) -> Void

    init(notify: @escaping @MainActor @Sendable (UUID) -> Void) {
        notifyClosure = notify
    }

    @MainActor
    func notify(_ artistID: UUID) {
        notifyClosure(artistID)
    }

    static func == (
        lhs: ArtistDetailReadinessObserver,
        rhs: ArtistDetailReadinessObserver
    ) -> Bool {
        lhs === rhs
    }
}

extension EnvironmentValues {
    @Entry var artistDetailReadinessObserver: ArtistDetailReadinessObserver?
}
