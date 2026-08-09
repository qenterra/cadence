import SwiftUI

struct ImportMusicScanningState: View {
    let candidates: [ImportCandidatePreview]
    let isPreview: Bool
    let progress: ImportInspectionProgress
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)

            VStack(spacing: 12) {
                if progress.totalCount == 0, !isPreview {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(CadenceTheme.primaryAccent)
                }

                Text(isPreview ? "Scanning Demo Library" : progress.phase.title)
                    .font(.title3.weight(.semibold))

                Text("Reading metadata, checking duplicates, and matching LRC files…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
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

            if isPreview {
                VStack(spacing: 0) {
                    ForEach(candidates.prefix(4)) { candidate in
                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .foregroundStyle(.tertiary)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
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

                            Spacer(minLength: 12)

                            Image(systemName: candidate.lyricStatus.symbolName)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(candidate.lyricStatus.title)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if candidate.id != candidates.prefix(4).last?.id {
                            Divider()
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

            Spacer(minLength: 24)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var displayedProgress: Double {
        isPreview ? 0.62 : progress.fractionCompleted
    }

    private var progressLabel: String {
        isPreview ? "62 of 100" : progress.primaryLabel
    }
}
