import QenTerraMediaComponents
import SwiftUI

struct MediaMetadataLink: View {
    let title: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.visualRegressionFreezesHighlights)
    private var disablesInteractiveHighlights

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
        QenTerraMediaComponents.MediaMetadataLink(
            title,
            accessibilityLabel: accessibilityLabel,
            freezesInteractionHighlights: disablesInteractiveHighlights,
            action: action
        )
    }
}
