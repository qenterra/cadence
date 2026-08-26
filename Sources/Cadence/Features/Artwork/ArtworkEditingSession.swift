import Foundation
import Observation

@MainActor
@Observable
final class ArtworkEditingSession {
    private(set) var revision = 0
    var pendingImportTarget: ArtworkTarget?
    var isImporterPresented = false
    var cropDraft: ArtworkCropDraft?
    var importError: String?

    func requestImport(for target: ArtworkTarget) {
        pendingImportTarget = target
        isImporterPresented = true
    }

    func prepareCrop(_ draft: ArtworkCropDraft) {
        cropDraft = draft
        pendingImportTarget = nil
        isImporterPresented = false
    }

    func finishCrop() {
        cropDraft = nil
    }

    func cancelCrop() {
        cropDraft = nil
    }

    func cancelImport() {
        pendingImportTarget = nil
        isImporterPresented = false
    }

    func presentImportError(_ message: String) {
        importError = message
        cancelImport()
    }

    func dismissImportError() {
        importError = nil
    }

    func recordArtworkChange() {
        revision += 1
    }
}
