import SwiftUI

extension EnvironmentValues {
    /// Replaces stateful AppKit controls with equivalent static symbols in
    /// visual-regression captures. Production keeps native controls.
    @Entry var visualRegressionUsesStableSystemControls = false

    /// Keeps pointer and focus highlights out of neutral-state captures.
    /// Production interactions remain unchanged because the default is false.
    @Entry var visualRegressionFreezesHighlights = false

    /// Public screenshots show the production surface, even when their data
    /// comes from an explicit in-memory preview fixture.
    @Entry var visualRegressionHidesPreviewChrome = false

    /// Opens the compact tag-entry field for its explicit visual-regression
    /// scenario. Production keeps the field collapsed by default.
    @Entry var visualRegressionShowsNowPlayingTagEntry = false

    /// Keeps repeated screenshot windows from re-running application startup
    /// and teardown work against their shared deterministic fixture.
    @Entry var visualRegressionPreservesFixtureState = false

    /// Freezes continuously animated decorative content at its seeded frame so
    /// screenshot comparisons measure layout and styling, not clock phase.
    @Entry var visualRegressionFreezesAnimatedContent = false
}
