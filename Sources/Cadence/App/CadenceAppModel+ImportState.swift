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

    var initialImportCandidates: [ImportCandidatePreview] {
        importWorkspaceState.initialCandidates
    }
}
