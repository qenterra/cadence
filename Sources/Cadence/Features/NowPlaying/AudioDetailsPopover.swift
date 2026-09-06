import QenTerraMediaComponents
import SwiftUI

struct AudioDetailsPopover: View {
    let presentation: AudioQualityPresentation

    var body: some View {
        AudioDetailsView(
            title: "Audio Details",
            subtitle: "Current playback path",
            details: CadencePlayerAdapters.audioDetails(presentation.details)
        )
    }
}
