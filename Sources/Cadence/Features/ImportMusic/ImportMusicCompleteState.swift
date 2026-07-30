import SwiftUI

struct ImportMusicCompleteState: View {
    let summary: ImportPreviewSummary
    let isPreview: Bool
    let importMore: () -> Void
    let viewImportedTracks: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            Image(systemName: "checkmark.circle")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(isPreview ? "Preview Import Complete" : "Import Complete")
                    .font(.title2.weight(.semibold))

                Text(
                    isPreview
                        ? "No files were copied in this design build."
                        : "Your music is ready in Cadence.library."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                summaryMetric(
                    value: summary.importedTrackCount.formatted(),
                    label: "Tracks"
                )
                Divider().frame(height: 44)
                summaryMetric(
                    value: summary.linkedLyricsCount.formatted(),
                    label: "Lyrics linked"
                )
                Divider().frame(height: 44)
                summaryMetric(
                    value: summary.exactDuplicateCount.formatted(),
                    label: "Duplicates skipped"
                )
                Divider().frame(height: 44)
                summaryMetric(
                    value: summary.issueCount.formatted(),
                    label: "Issues reviewed"
                )
            }
            .frame(maxWidth: 650)
            .padding(.vertical, 18)
            .background(CadenceTheme.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(
                isPreview
                    ? "\(summary.importedSizeText) selected for Cadence.library"
                    : "\(summary.importedSizeText) added to Cadence.library"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Import More", action: importMore)
                    .buttonStyle(.bordered)

                Button("View Imported Tracks", action: viewImportedTracks)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

            Spacer(minLength: 24)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summaryMetric(
        value: String,
        label: String
    ) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
