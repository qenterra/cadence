import SwiftUI

struct ImportMusicCompleteState: View {
    let summary: ImportPreviewSummary
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let sizeSummary: LocalizedStringKey
    let importMore: () -> Void
    let viewImportedTracks: () -> Void

    var body: some View {
        VStack(spacing: CadenceLayout.pageInset) {
            Spacer(minLength: CadenceLayout.pageInset)

            Image(systemName: "checkmark.circle")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            VStack(spacing: CadenceLayout.compactGap) {
                Text(title)
                    .font(.title2.weight(.semibold))

                Text(message)
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
            .padding(.vertical, CadenceLayout.contentGap)
            .background(CadenceTheme.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup, style: .continuous))

            Text(sizeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: CadenceLayout.compactGap) {
                Button("Import More", action: importMore)
                    .buttonStyle(.bordered)

                Button("View Imported Tracks", action: viewImportedTracks)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

            Spacer(minLength: CadenceLayout.pageInset)
        }
        .padding(CadenceLayout.sectionGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summaryMetric(
        value: String,
        label: String
    ) -> some View {
        VStack(spacing: CadenceLayout.textStack) {
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
