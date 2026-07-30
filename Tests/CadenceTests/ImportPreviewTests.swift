@testable import Cadence
import Testing

struct ImportPreviewTests {
    private let candidates = [ImportCandidatePreview].mockImportCandidates

    @Test("Import classifications map to stable review categories")
    func categories() {
        let categories = Dictionary(
            uniqueKeysWithValues: candidates.map {
                ($0.id, $0.classification.reviewCategory)
            }
        )

        #expect(categories["midnight-static"] == .ready)
        #expect(categories["exact-night-drive"] == .duplicates)
        #expect(categories["possible-afterimage"] == .duplicates)
        #expect(categories["malformed-falling-signals"] == .issues)
    }

    @Test("Eligibility distinguishes blocking and lyric-only issues")
    func eligibility() throws {
        let exact = try #require(
            candidates.first { $0.id == "exact-night-drive" }
        )
        let possible = try #require(
            candidates.first { $0.id == "possible-afterimage" }
        )
        let malformedLyrics = try #require(
            candidates.first { $0.id == "malformed-falling-signals" }
        )
        let unsupported = try #require(
            candidates.first { $0.id == "unsupported-demo" }
        )

        #expect(!exact.isEligible)
        #expect(possible.isEligible)
        #expect(malformedLyrics.isEligible)
        #expect(!unsupported.isEligible)
    }

    @Test("Only safe candidates start included")
    func defaultInclusion() {
        let includedIDs = Set(
            candidates
                .filter(\.isIncludedByDefault)
                .map(\.id)
        )

        #expect(includedIDs.contains("midnight-static"))
        #expect(includedIDs.contains("malformed-falling-signals"))
        #expect(!includedIDs.contains("possible-afterimage"))
        #expect(!includedIDs.contains("exact-night-drive"))
        #expect(!includedIDs.contains("unsupported-demo"))
    }

    @Test("Preview stage and review category titles are user facing")
    func titles() {
        #expect(ImportPreviewStage.complete.title == "Complete")
        #expect(ImportReviewCategory.duplicates.title == "Duplicates")
        #expect(
            ImportCandidateClassification.exactDuplicate.title
                == "Already in Library"
        )
    }
}
