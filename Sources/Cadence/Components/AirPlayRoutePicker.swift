import AVFoundation
import QenTerraMediaComponents
import SwiftUI

struct AirPlayRoutePicker: View {
    let player: AVPlayer?

    var body: some View {
        QenTerraMediaComponents.AirPlayRoutePicker(player: player)
    }
}
