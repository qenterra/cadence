@testable import Cadence
import Testing

@MainActor
struct ImportPreviewAppModelTests {
    @Test("Preview lifecycle stays deterministic and in memory")
    func lifecycle() {
        let model = CadenceAppModel.testFixture()

        model.startImportPreview()
        #expect(model.importPreviewStage == .scanning)

        model.completeImportPreviewScan()
        #expect(model.importPreviewStage == .review)
        #expect(!model.selectedImportCandidateIDs.isEmpty)

        model.beginImportPreview()
        #expect(model.importPreviewStage == .importing)

        model.completeImportPreview()
        #expect(model.importPreviewStage == .complete)
    }

    @Test("Cancel returns scanning to an empty preview")
    func cancel() {
        let model = CadenceAppModel.testFixture()

        model.startImportPreview()
        model.cancelImportPreviewScan()

        #expect(model.importPreviewStage == .empty)
        #expect(model.selectedImportCandidateIDs.isEmpty)
    }

    @Test("Review tabs expose their own canonical candidates")
    func reviewTabs() {
        let model = CadenceAppModel.testFixture()
        model.showImportPreviewStage(.review)

        #expect(
            model.visibleImportCandidates.allSatisfy {
                $0.classification.reviewCategory == .ready
            }
        )

        model.selectImportReviewCategory(.duplicates)

        #expect(
            model.visibleImportCandidates.allSatisfy {
                $0.classification.reviewCategory == .duplicates
            }
        )
    }

    @Test("Select All targets only eligible candidates in the active tab")
    func selectAll() {
        let model = CadenceAppModel.testFixture()
        model.showImportPreviewStage(.review)
        model.selectImportReviewCategory(.duplicates)

        model.selectAllImportCandidates()

        #expect(
            model.selectedImportCandidateIDs == Set(["possible-afterimage"])
        )
    }

    @Test("Inclusion ignores exact duplicates and blocking issues")
    func inclusionSafety() {
        let model = CadenceAppModel.testFixture()

        model.toggleImportCandidateInclusion("exact-night-drive")
        model.toggleImportCandidateInclusion("unsupported-demo")
        model.toggleImportCandidateInclusion("possible-afterimage")

        #expect(
            !model.includedImportCandidateIDs.contains("exact-night-drive")
        )
        #expect(!model.includedImportCandidateIDs.contains("unsupported-demo"))
        #expect(model.includedImportCandidateIDs.contains("possible-afterimage"))
    }

    @Test("Summary derives from included candidates")
    func summary() {
        let model = CadenceAppModel.testFixture()
        let initialSummary = model.importPreviewSummary

        model.toggleImportCandidateInclusion("possible-afterimage")
        let updatedSummary = model.importPreviewSummary

        #expect(
            updatedSummary.importedTrackCount
                == initialSummary.importedTrackCount + 1
        )
        #expect(
            updatedSummary.importedSizeInBytes
                == initialSummary.importedSizeInBytes + 104_000_000
        )
    }

    @Test("View Imported Tracks returns to Library")
    func viewImportedTracks() {
        let model = CadenceAppModel.testFixture()
        model.requestNavigationDestination(.importMusic)
        model.showImportPreviewStage(.complete)

        model.viewImportedPreviewTracks()

        #expect(model.selectedDestination == .library)
        #expect(model.selectedTrackID == 1)
    }

    @Test("Preview State holds transient stages for inspection")
    func previewStateInspector() {
        let model = CadenceAppModel.testFixture()

        model.showImportPreviewStage(.scanning)

        #expect(model.importPreviewStage == .scanning)
        #expect(!model.isImportPreviewAutoAdvanceEnabled)

        model.startImportPreview()

        #expect(model.isImportPreviewAutoAdvanceEnabled)
    }

    @Test("Accepted drop opens deterministic scanning preview")
    func acceptedDrop() {
        let model = CadenceAppModel.testFixture()
        model.setImportDropTargeted(true)

        model.acceptImportPreviewDrop()

        #expect(!model.isImportDropTargeted)
        #expect(model.selectedDestination == .importMusic)
        #expect(model.importPreviewStage == .scanning)
        #expect(model.isImportPreviewAutoAdvanceEnabled)
    }

    @Test("Active navigation no longer contains Graph")
    func navigationDestinations() {
        #expect(
            NavigationDestination.allCases == [
                .home,
                .library,
                .allTracks,
                .albums,
                .artists,
                .tags,
                .smartCollections,
                .playlists,
                .importMusic,
                .trash,
            ]
        )
    }

    @Test("Home is a first-class navigation destination")
    func homeNavigationDestination() {
        #expect(
            NavigationDestination(rawValue: "home")?.title == "Home"
        )
    }

    @Test("New app models open Home")
    @MainActor
    func defaultNavigationDestination() {
        let model = CadenceAppModel.testFixture()

        #expect(model.selectedDestination.rawValue == "home")
    }

    @Test("Settings is not a navigation destination")
    func settingsBelongToTheApplicationMenu() {
        #expect(NavigationDestination(rawValue: "settings") == nil)
    }
}
