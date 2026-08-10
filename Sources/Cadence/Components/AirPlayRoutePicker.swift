import AVFoundation
import AVKit
import SwiftUI

struct AirPlayRoutePicker: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context _: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.player = player
        return picker
    }

    func updateNSView(
        _ picker: AVRoutePickerView,
        context _: Context
    ) {
        picker.player = player
    }
}
