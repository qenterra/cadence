import SwiftUI

struct AudioDetailsPopover: View {
    let presentation: AudioQualityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Audio Details")
                    .font(.headline)
                Text("Current playback path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 9) {
                ForEach(Array(presentation.details.enumerated()), id: \.offset) { _, detail in
                    GridRow {
                        Text(detail.label)
                            .foregroundStyle(.secondary)
                        Text(detail.value)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .font(.callout)
        }
        .padding(20)
        .frame(width: 360)
    }
}
