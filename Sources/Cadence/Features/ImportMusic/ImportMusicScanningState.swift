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
                ProgressView()
                    .controlSize(.large)

                Text(isPreview ? "Scanning Demo Library" : "Scanning Music")
                    .font(.title3.weight(.semibold))

                Text("Reading metadata, checking duplicates, and matching LRC files…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: displayedProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 520)
                .accessibilityLabel("Scan progress")
                .accessibilityValue(
                    "\(Int(displayedProgress * 100)) percent"
                )

            if !isPreview, let filename = progress.currentFilename {
                Text(filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 520)
            }

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
}
