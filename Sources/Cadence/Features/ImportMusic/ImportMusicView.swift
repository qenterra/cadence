import SwiftUI

struct ImportMusicView: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isKeyboardTarget

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            stateContent
                .id(model.importPreviewStage)
                .transition(.opacity)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: CadenceTheme.motionReplace),
                    value: model.importPreviewStage
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.contentBackground)
        .focusable()
        .focusEffectDisabled()
        .focused($isKeyboardTarget)
        .onAppear {
            isKeyboardTarget = true
        }
        .onKeyPress("a", phases: .down) { keyPress in
            guard
                keyPress.modifiers == .command,
                model.importPreviewStage == .review
            else {
                return .ignored
            }

            model.selectAllImportCandidates()
            return .handled
        }
        .onKeyPress(.space, phases: .down) { _ in
            guard model.importPreviewStage == .review else {
                return .ignored
            }

            model.toggleSelectedImportCandidateInclusion()
            return .handled
        }
        .alert(
            "Couldn’t Scan Music",
            isPresented: Binding(
                get: { model.importScanError != nil },
                set: { isPresented in
                    if !isPresented {
                        model.clearImportScanError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.clearImportScanError()
            }
        } message: {
            Text(model.importScanError ?? "The source could not be read.")
        }
        .alert(
            "Couldn’t Import Music",
            isPresented: Binding(
                get: { model.importOperationError != nil },
                set: { isPresented in
                    if !isPresented {
                        model.clearImportOperationError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.clearImportOperationError()
            }
        } message: {
            Text(
                model.importOperationError
                    ?? "The selected music could not be imported."
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(pageTitle)
                    .font(.title2.weight(.semibold))

                Text(pageSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            if model.runtimeEnvironment.previewFixture != nil {
                ImportMusicPreviewHeaderControls(model: model)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var stateContent: some View {
        if case let .unavailable(message) = model.importRuntimeAvailability {
            ContentUnavailableView {
                Label(
                    "Import Unavailable",
                    systemImage: "exclamationmark.triangle"
                )
            } description: {
                Text(message)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.runtimeEnvironment.previewFixture != nil {
            ImportMusicPreviewStageContent(model: model)
        } else {
            productionImportStageContent
        }
    }

    @ViewBuilder
    private var productionImportStageContent: some View {
        switch model.importPreviewStage {
        case .empty:
            ImportMusicEmptyState(
                supportingText: "Cadence will copy included audio into ~/Music/Cadence.library only after Review.",
                footnote: nil,
                startScanning: model.chooseImportFolder
            )
        case .scanning:
            ImportMusicScanningState(
                sampleCandidates: nil,
                title: LocalizedStringKey(model.importScanProgress.phase.title),
                progress: model.importScanProgress,
                displayedProgress: model.importScanProgress.fractionCompleted,
                progressLabel: model.importScanProgress.primaryLabel,
                cancel: model.cancelImportPreviewScan
            )
        case .review:
            productionReview(isImporting: false)
        case .importing:
            productionReview(isImporting: true)
        case .complete:
            ImportMusicCompleteState(
                summary: model.importPreviewSummary,
                title: "Import Complete",
                message: "Your music is ready in Cadence.library.",
                sizeSummary: "\(model.importPreviewSummary.importedSizeText) added to Cadence.library",
                importMore: model.importMorePreviewMusic,
                viewImportedTracks: model.viewImportedPreviewTracks
            )
        }
    }

    private func productionReview(isImporting: Bool) -> some View {
        ImportMusicReview(
            model: model,
            isImporting: isImporting,
            importingStatusLabel: "Import in progress",
            importProgressText: productionImportProgressText,
            canCancelImport: model.managedImportProgress?.isCommitting == false,
            cancelImport: model.cancelManagedImport
        )
    }

    private var productionImportProgressText: LocalizedStringKey {
        guard let progress = model.managedImportProgress else {
            return "Preparing Cadence.library…"
        }
        if progress.isCommitting {
            return LocalizedStringKey(progress.phase.title)
        }
        return "\(progress.phase.title) · \(progress.primaryLabel)"
    }

    private var pageTitle: String {
        switch model.importPreviewStage {
        case .empty:
            "Import Music"
        case .scanning:
            "Scanning Music"
        case .review:
            "Import Review"
        case .importing:
            "Importing Music"
        case .complete:
            "Import Complete"
        }
    }

    private var pageSubtitle: String {
        switch model.importPreviewStage {
        case .empty:
            "Add a folder or drop music into Cadence"
        case .scanning:
            "Reading metadata without changing the source"
        case .review:
            "Choose exactly what belongs in Cadence.library"
        case .importing:
            "Copying the approved selection into Cadence.library"
        case .complete:
            "The import report is ready"
        }
    }
}
