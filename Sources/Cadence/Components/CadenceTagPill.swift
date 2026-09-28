import SwiftUI

enum CadenceTagPillMetrics {
    static let height = CGFloat(26)
}

struct CadenceTagPillPresentation: Equatable, Sendable {
    let showsRemoveButton: Bool
    let reservedTrailingWidth: CGFloat

    static func resolve(
        isHovered _: Bool,
        isFocused _: Bool,
        hasRemoveAction: Bool
    ) -> Self {
        Self(
            showsRemoveButton: hasRemoveAction,
            reservedTrailingWidth: hasRemoveAction ? 18 : 0
        )
    }
}

struct CadenceTagPill: View {
    let title: String
    let removeAction: (() -> Void)?
    let removeAccessibilityLabel: String?
    let action: () -> Void

    @FocusState private var isFocused: Bool

    init(
        title: String,
        removeAction: (() -> Void)? = nil,
        removeAccessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.removeAction = removeAction
        self.removeAccessibilityLabel = removeAccessibilityLabel
        self.action = action
    }

    var body: some View {
        let presentation = CadenceTagPillPresentation.resolve(
            isHovered: false,
            isFocused: isFocused,
            hasRemoveAction: removeAction != nil
        )

        HStack(spacing: 3) {
            Button(action: action) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isFocused)
            .accessibilityLabel("Edit \(title)")

            if let removeAction {
                ZStack {
                    Button(action: removeAction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 16, height: 16)
                            .background(.primary.opacity(0.08), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary.opacity(0.72))
                    .focused($isFocused)
                    .opacity(presentation.showsRemoveButton ? 1 : 0)
                    .disabled(!presentation.showsRemoveButton)
                    .accessibilityHidden(!presentation.showsRemoveButton)
                    .accessibilityLabel(
                        removeAccessibilityLabel ?? "Remove \(title)"
                    )
                }
                .frame(width: presentation.reservedTrailingWidth)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, removeAction == nil ? 10 : 6)
        .frame(height: CadenceTagPillMetrics.height)
        .background(CadenceTheme.subduedFill, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
        }
    }
}
