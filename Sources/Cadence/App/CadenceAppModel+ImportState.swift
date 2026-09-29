extension CadenceAppModel {
    var isImportPreviewAutoAdvanceEnabled: Bool {
        get { importWorkspaceState.autoAdvanceEnabled }
        set { importWorkspaceState.autoAdvanceEnabled = newValue }
    }

    var importScanError: String? {
        get { importWorkspaceState.scanError }
        set { importWorkspaceState.scanError = newValue }
    }

    var importOperationError: String? {
        get { importWorkspaceState.operationError }
        set { importWorkspaceState.operationError = newValue }
    }

    var managedImportProgress: ManagedImportProgress? {
        get { importWorkspaceState.progress }
        set { importWorkspaceState.progress = newValue }
    }

    var managedImportCompletion: ManagedImportCompletion? {
        get { importWorkspaceState.completion }
        set { importWorkspaceState.completion = newValue }
    }

    var unsupportedImportFiles: [SourceScanner.UnsupportedFile] {
        get { importWorkspaceState.unsupportedFiles }
        set { importWorkspaceState.unsupportedFiles = newValue }
    }

    var unsupportedImportMessage: String? {
        guard !unsupportedImportFiles.isEmpty else { return nil }
        let names = unsupportedImportFiles.prefix(4).map(\.relativePath).joined(separator: "\n")
        let remainder = unsupportedImportFiles.count - min(unsupportedImportFiles.count, 4)
        if remainder > 0 {
            return "Cadence skipped \(unsupportedImportFiles.count) unsupported files:\n"
                + "\(names)\n…and \(remainder) more."
        }
        return "Cadence skipped unsupported files:\n\(names)"
    }

    func clearUnsupportedImportNotice() {
        unsupportedImportFiles = []
    }

    var initialImportCandidates: [ImportCandidatePreview] {
        importWorkspaceState.initialCandidates
    }
}
