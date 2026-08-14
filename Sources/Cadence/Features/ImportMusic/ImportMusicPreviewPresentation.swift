import SwiftUI

struct ImportMusicPreviewHeaderControls: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        Label("Design Preview · No files are copied", systemImage: "eye")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CadenceTheme.subduedFill, in: Capsule())
            .accessibilityLabel("Design preview. No files are copied.")

        Menu {
            ForEach(ImportPreviewStage.allCases) { stage in
                Button(stage.title) {
                    model.showImportPreviewStage(stage)
                }
            }
        } label: {
            Label("Preview State", systemImage: "switch.2")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Inspect each mock import state")
    }
}

struct ImportMusicPreviewStageContent: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        Group {
            switch model.importPreviewStage {
            case .empty:
                ImportMusicEmptyState(
                    supportingText: """
                    A future import will copy supported audio into \
                    ~/Music/Cadence.library after Review.
                    """,
                    footnote: "This build only previews the workflow.",
                    startScanning: model.chooseImportFolder
                )
            case .scanning:
                ImportMusicScanningState(
                    sampleCandidates: model.importCandidates,
                    title: "Scanning Demo Library",
                    progress: model.importScanProgress,
                    displayedProgress: 0.62,
                    progressLabel: "62 of 100",
                    cancel: model.cancelImportPreviewScan
                )
            case .review:
                previewReview(isImporting: false)
            case .importing:
                previewReview(isImporting: true)
            case .complete:
                ImportMusicCompleteState(
                    summary: model.importPreviewSummary,
                    title: "Preview Import Complete",
                    message: "No files were copied in this design build.",
                    sizeSummary: "\(model.importPreviewSummary.importedSizeText) selected for Cadence.library",
                    importMore: model.importMorePreviewMusic,
                    viewImportedTracks: model.viewImportedPreviewTracks
                )
            }
        }
        .task(id: model.importPreviewStage) {
            await advanceTransientStage()
        }
    }

    private func previewReview(isImporting: Bool) -> some View {
        ImportMusicReview(
            model: model,
            isImporting: isImporting,
            importingStatusLabel: "Preview import in progress",
            importProgressText: "Simulating the managed-library copy…",
            canCancelImport: true,
            cancelImport: model.importMorePreviewMusic
        )
    }

    private func advanceTransientStage() async {
        let startingStage = model.importPreviewStage
        guard model.isImportPreviewAutoAdvanceEnabled,
              startingStage == .scanning || startingStage == .importing else {
            return
        }

        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled,
              model.importPreviewStage == startingStage else {
            return
        }

        switch startingStage {
        case .scanning:
            model.completeImportPreviewScan()
        case .importing:
            model.completeImportPreview()
        case .empty, .review, .complete:
            break
        }
    }
}
