import QenTerraComponents
import SwiftUI

struct CadenceSeparator: View {
    var axis: Axis = .horizontal

    var body: some View {
        DesignSeparator(
            orientation: axis == .vertical ? .vertical : .horizontal
        )
    }
}
