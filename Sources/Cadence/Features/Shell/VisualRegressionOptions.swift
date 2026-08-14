import SwiftUI

extension EnvironmentValues {
    /// Replaces stateful AppKit controls with equivalent static symbols in
    /// visual-regression captures. Production keeps native controls.
    @Entry var visualRegressionUsesStableSystemControls = false

    /// Keeps pointer and focus highlights out of neutral-state captures.
    /// Production interactions remain unchanged because the default is false.
    @Entry var visualRegressionDisablesInteractiveHighlights = false
}
