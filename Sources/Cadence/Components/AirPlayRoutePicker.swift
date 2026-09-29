import AVFoundation
import AVKit
import SwiftUI

final class CadenceAirPlayRoutePickerView: AVRoutePickerView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

struct AirPlayRoutePicker: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context _: Context) -> CadenceAirPlayRoutePickerView {
        let picker = CadenceAirPlayRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.player = Self.routingPlayer(player)
        return picker
    }

    func updateNSView(
        _ picker: CadenceAirPlayRoutePickerView,
        context _: Context
    ) {
        picker.player = Self.routingPlayer(player)
    }

    static func routingPlayer(_ player: AVPlayer?) -> AVPlayer? {
        guard player?.currentItem != nil else { return nil }
        return player
    }
}
