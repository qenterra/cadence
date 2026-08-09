@testable import Cadence
import Testing

struct ReleaseClassificationTests {
    @Test("Fallback classification follows track and duration boundaries")
    func fallbackBoundaries() {
        #expect(
            ReleaseKind.classify(
                metadata: nil,
                trackCount: 3,
                duration: 1800
            ) == .single
        )
        #expect(
            ReleaseKind.classify(
                metadata: nil,
                trackCount: 4,
                duration: 1800
            ) == .ep
        )
        #expect(
            ReleaseKind.classify(
                metadata: nil,
                trackCount: 6,
                duration: 1800
            ) == .ep
        )
        #expect(
            ReleaseKind.classify(
                metadata: nil,
                trackCount: 7,
                duration: 1200
            ) == .album
        )
        #expect(
            ReleaseKind.classify(
                metadata: nil,
                trackCount: 2,
                duration: 1800.1
            ) == .album
        )
    }

    @Test("Explicit release metadata wins and normalizes common spellings")
    func explicitMetadata() {
        #expect(
            ReleaseKind.classify(
                metadata: "E.P.",
                trackCount: 12,
                duration: 4000
            ) == .ep
        )
        #expect(
            ReleaseKind.classify(
                metadata: "single",
                trackCount: 9,
                duration: 3000
            ) == .single
        )
        #expect(
            ReleaseKind.classify(
                metadata: "LP",
                trackCount: 1,
                duration: 120
            ) == .album
        )
    }
}
