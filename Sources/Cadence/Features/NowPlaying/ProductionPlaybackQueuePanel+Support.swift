import SwiftUI

enum ProductionQueueSectionKind {
    case history
    case current
    case upNext
}

enum ProductionQueueDropTarget: Equatable {
    case track(UUID)
    case end
}

struct ProductionQueueInsertionIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.9))
            .frame(height: 2)
            .padding(.horizontal, 8)
            .offset(y: -1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ProductionQueueRowInteractionModifier: ViewModifier {
    let isUpNext: Bool
    let isSelected: Bool
    let play: () -> Void
    let select: () -> Void

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                BrowserRowSurface(
                    isSelected: isSelected,
                    isHovered: false,
                    isFocused: false
                )
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded(perform: play)
            )
            .highPriorityGesture(
                TapGesture().onEnded {
                    if isUpNext {
                        select()
                    }
                }
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(CadenceTheme.separator)
                    .frame(height: 1)
            }
    }
}

struct ProductionQueueRowDropModifier: ViewModifier {
    let item: PlaybackQueueTrackProjection
    let isUpNext: Bool
    let payload: String
    @Binding var activeDropTarget: ProductionQueueDropTarget?
    let reorder: ([String]) -> Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if activeDropTarget == .track(item.id) {
                    ProductionQueueInsertionIndicator()
                }
            }
            .modifier(
                ProductionQueueDragModifier(
                    payload: payload,
                    item: item,
                    isEnabled: isUpNext
                )
            )
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

struct ProductionQueueDragModifier: ViewModifier {
    let payload: String
    let item: PlaybackQueueTrackProjection
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(payload) {
                ProductionQueueDragPreview(item: item)
            }
        } else {
            content
        }
    }
}

private struct ProductionQueueDragPreview: View {
    let item: PlaybackQueueTrackProjection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.track == nil ? "questionmark" : "music.note")
                .frame(width: 38, height: 38)
                .background(CadenceTheme.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.track?.title ?? "Unavailable Track")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(item.track.map { "\($0.artist) · \($0.album)" }
                    ?? item.id.uuidString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(width: 330, alignment: .leading)
        .background(CadenceTheme.opaqueSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.14))
        }
        .shadow(color: .black.opacity(0.38), radius: 16, y: 8)
    }
}
