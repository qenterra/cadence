import SwiftUI

struct MediaMetadataLink: View {
    let title: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.visualRegressionDisablesInteractiveHighlights)
    private var disablesInteractiveHighlights
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    init(
        _ title: String,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
            ?? "Open \(title)"
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isHighlighted ? Color.primary : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(
            reduceMotion ? nil : .easeOut(duration: CadenceTheme.motionHover),
            value: isHighlighted
        )
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private var isHighlighted: Bool {
        !disablesInteractiveHighlights && (isHovered || isFocused)
    }
}
