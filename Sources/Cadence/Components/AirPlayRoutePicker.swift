import AVFoundation
import AVKit
import SwiftUI

struct AirPlayRoutePicker: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context _: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.player = Self.routingPlayer(player)
        return picker
    }

    func updateNSView(
        _ picker: AVRoutePickerView,
        context _: Context
    ) {
        picker.player = Self.routingPlayer(player)
    }

    static func routingPlayer(
        _ player: AVPlayer?
    ) -> AVPlayer? {
        guard player?.currentItem != nil else {
            return nil
        }
        return player
    }
}
