import QenTerraMediaComponents
import SwiftUI

enum ProductionQueueSectionKind {
    case current
    case upNext
}

enum ProductionQueueDropTarget: Equatable {
    case track(UUID)
    case end
}

struct ProductionQueueRowDropModifier: ViewModifier {
    let item: PlaybackQueueTrackProjection
    let isUpNext: Bool
    @Binding var activeDropTarget: ProductionQueueDropTarget?
    let reorder: ([String]) -> Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if activeDropTarget == .track(item.id) {
                    QueueInsertionIndicator()
                }
            }
            .dropDestination(for: String.self) { payloads, _ in
                isUpNext && reorder(payloads)
            } isTargeted: { isTargeted in
                guard isUpNext else {
                    return
                }
                activeDropTarget = isTargeted ? .track(item.id) : nil
            }
    }
}
