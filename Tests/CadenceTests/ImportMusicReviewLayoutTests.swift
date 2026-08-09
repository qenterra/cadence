@testable import Cadence
import Testing

struct ImportMusicReviewLayoutTests {
    @Test("Minimum window workspace uses compact import columns")
    func minimumWindowUsesCompactColumns() {
        let workspaceWidth = 1080.0
            - NavigationRailMetrics.expandedWidth
            - 1

        #expect(ImportMusicReviewLayout.mode(for: workspaceWidth) == .compact)
        #expect(
            ImportMusicReviewLayout.minimumContentWidth(for: .compact)
                <= workspaceWidth
        )
    }

    @Test("Wide workspace preserves the complete review table")
    func wideWorkspaceUsesFullColumns() {
        #expect(ImportMusicReviewLayout.mode(for: 1200) == .full)
        #expect(
            ImportMusicReviewLayout.minimumContentWidth(for: .full)
                > ImportMusicReviewLayout.minimumContentWidth(for: .compact)
        )
    }
}
