import SwiftUI

extension EnvironmentValues {
    /// Replaces stateful AppKit controls with equivalent static symbols in
    /// visual-regression captures. Production keeps native controls.
    @Entry var visualRegressionUsesStableSystemControls = false
}
