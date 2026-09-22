import SwiftUI

struct ImportMusicPreviewHeaderControls: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        Label("Preview · Files aren’t copied", systemImage: "eye")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CadenceTheme.subduedFill, in: Capsule())
            .accessibilityLabel("Preview. Files aren’t copied.")

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
        .help("Choose a preview state")
    }
}

struct ImportMusicPreviewStageContent: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        Group {
            switch model.importPreviewStage {
            case .empty:
                ImportMusicEmptyState(
                    supportingText: "Review supported audio before choosing what to import.",
                    footnote: "Preview data only.",
                    startScanning: model.chooseImportFolder
                )
            case .scanning:
                ImportMusicScanningState(
                    sampleCandidates: model.importCandidates,
                    title: "Scanning Sample Library",
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
                    title: "Preview Complete",
                    message: "No files were copied.",
                    sizeSummary: "\(model.importPreviewSummary.importedSizeText) selected",
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
            importingStatusLabel: "Previewing import",
            importProgressText: "Previewing the library copy…",
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
