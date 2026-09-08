import QenTerraComponents
import SwiftUI

struct ImportMusicScanningState: View {
    let sampleCandidates: [ImportCandidatePreview]?
    let title: String
    let progress: ImportInspectionProgress
    let displayedProgress: Double
    let progressLabel: String
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: CadenceLayout.panelInset) {
            Spacer(minLength: CadenceLayout.pageInset)

            OperationStateView(
                state: .preparing(
                    title: title,
                    message: "Reading metadata, checking duplicates, and matching LRC files…"
                ),
                symbolName: progress.totalCount == 0 && sampleCandidates == nil
                    ? nil
                    : "waveform.badge.magnifyingglass",
                visualStyle: .cadenceScanning
            )

            VStack(spacing: CadenceLayout.compactGap) {
                ProgressView(value: displayedProgress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Scan progress")
                    .accessibilityValue(progressLabel)

                Text(progressLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: 520)

            if let sampleCandidates {
                VStack(spacing: 0) {
                    ForEach(sampleCandidates.prefix(4)) { candidate in
                        HStack(spacing: CadenceLayout.controlGap) {
                            Image(systemName: "waveform")
                                .foregroundStyle(.tertiary)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: CadenceLayout.textStack) {
                                Text(candidate.sourceFilename)
                                    .font(.callout)
                                    .lineLimit(1)

                                Text(
                                    "\(candidate.format) · "
                                        + candidate.fileSizeText
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: CadenceLayout.controlGap)

                            Image(systemName: candidate.lyricStatus.symbolName)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(candidate.lyricStatus.title)
                        }
                        .padding(.horizontal, CadenceLayout.contentGap)
                        .padding(.vertical, CadenceLayout.compactGap)

                        if candidate.id != sampleCandidates.prefix(4).last?.id {
                            DesignSeparator()
                                .padding(.leading, 44)
                        }
                    }
                }
                .frame(maxWidth: 620)
                .background(CadenceTheme.secondarySurface)
                .clipShape(
                    RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup, style: .continuous)
                )
            }

            Button("Cancel", action: cancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Spacer(minLength: CadenceLayout.pageInset)
        }
        .padding(CadenceLayout.sectionGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
