@testable import Cadence
import Foundation
import Testing

@MainActor
struct ArtworkEditingSessionTests {
    @Test("Artwork import advances through one owned session")
    func importLifecycle() {
        let session = ArtworkEditingSession()
        let target = ArtworkTarget.managedAlbum(UUID())
        let draft = ArtworkCropDraft(
            target: target,
            title: "Album",
            data: Data([0x01, 0x02]),
            shape: .square
        )

        session.requestImport(for: target)
        #expect(session.pendingImportTarget == target)
        #expect(session.isImporterPresented)

        session.prepareCrop(draft)
        #expect(session.pendingImportTarget == nil)
        #expect(!session.isImporterPresented)
        #expect(session.cropDraft == draft)

        session.finishCrop()
        #expect(session.cropDraft == nil)
    }

    @Test("Artwork errors cancel only the pending import")
    func importErrorLifecycle() {
        let session = ArtworkEditingSession()
        let target = ArtworkTarget.managedTrack(UUID())

        session.requestImport(for: target)
        session.presentImportError("Unreadable artwork")

        #expect(session.pendingImportTarget == nil)
        #expect(!session.isImporterPresented)
        #expect(session.importError == "Unreadable artwork")

        session.dismissImportError()
        #expect(session.importError == nil)
    }

    @Test("CadenceAppModel forwards artwork state to the injected owner")
    func modelUsesInjectedSession() {
        let session = ArtworkEditingSession()
        let model = CadenceAppModel(
            runtimeEnvironment: .preview(CadencePreviewFixture()),
            importRuntimeAvailability: .preview,
            librarySession: .preview(),
            artworkEditingSession: session
        )

        model.artworkImportError = "Current error"
        session.recordArtworkChange()

        #expect(model.artworkEditingSession === session)
        #expect(session.importError == "Current error")
        #expect(model.artworkRevision == 1)
    }
}
