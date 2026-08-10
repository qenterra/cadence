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
        .task(id: model.importPreviewStage) {
            await advanceTransientPreviewStage()
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

            if model.isImportPreviewMode {
                Label("Design Preview · No files are copied", systemImage: "eye")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(CadenceTheme.subduedFill, in: Capsule())
                    .accessibilityLabel(
                        "Design preview. No files are copied."
                    )

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
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.importPreviewStage {
        case .empty:
            ImportMusicEmptyState(
                isPreview: model.isImportPreviewMode,
                startScanning: model.chooseImportFolder
            )
        case .scanning:
            ImportMusicScanningState(
                candidates: model.importCandidates,
                isPreview: model.isImportPreviewMode,
                progress: model.importScanProgress,
                cancel: model.cancelImportPreviewScan
            )
        case .review:
            ImportMusicReview(model: model, isImporting: false)
        case .importing:
            ImportMusicReview(model: model, isImporting: true)
        case .complete:
            ImportMusicCompleteState(
                summary: model.importPreviewSummary,
                isPreview: model.isImportPreviewMode,
                importMore: model.importMorePreviewMusic,
                viewImportedTracks: model.viewImportedPreviewTracks
            )
        }
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
            if model.isImportPreviewMode {
                "Reading Demo Library without changing the source"
            } else {
                "Reading metadata without changing the source"
            }
        case .review:
            "Choose exactly what belongs in Cadence.library"
        case .importing:
            "Copying the approved selection into Cadence.library"
        case .complete:
            "The import report is ready"
        }
    }

    private func advanceTransientPreviewStage() async {
        guard model.isImportPreviewMode else {
            return
        }
        let startingStage = model.importPreviewStage
        guard
            model.isImportPreviewAutoAdvanceEnabled,
            startingStage == .scanning || startingStage == .importing
        else {
            return
        }

        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled, model.importPreviewStage == startingStage else {
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
