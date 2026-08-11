import AppKit
import SwiftUI

enum RhythmKeyAction: Equatable {
    case hit(RhythmLane)
    case exitCadenceMode
}

enum RhythmKeyDecision {
    static func decide(
        keyCode: UInt16,
        isNowPlayingVisible: Bool,
        hasEditableFirstResponder: Bool,
        isBlockedByModal: Bool
    ) -> RhythmLane? {
        guard case let .hit(lane) = decideAction(
            keyCode: keyCode,
            isNowPlayingVisible: isNowPlayingVisible,
            isCadenceModeActive: false,
            hasEditableFirstResponder: hasEditableFirstResponder,
            isBlockedByModal: isBlockedByModal
        ) else {
            return nil
        }
        return lane
    }

    static func decideAction(
        keyCode: UInt16,
        isNowPlayingVisible: Bool,
        isCadenceModeActive: Bool,
        hasEditableFirstResponder: Bool,
        isBlockedByModal: Bool
    ) -> RhythmKeyAction? {
        guard
            isNowPlayingVisible,
            !hasEditableFirstResponder,
            !isBlockedByModal
        else {
            return nil
        }

        switch keyCode {
        case 6:
            return .hit(.left)
        case 7:
            return .hit(.right)
        case 53 where isCadenceModeActive:
            return .exitCadenceMode
        default:
            return nil
        }
    }
}

struct RhythmKeyboardCapture: NSViewRepresentable {
    let isCadenceModeActive: Bool
    let onHit: @MainActor (RhythmLane) -> Void
    let onExitCadenceMode: @MainActor () -> Void

    init(
        isCadenceModeActive: Bool = false,
        onHit: @escaping @MainActor (RhythmLane) -> Void,
        onExitCadenceMode: @escaping @MainActor () -> Void = {}
    ) {
        self.isCadenceModeActive = isCadenceModeActive
        self.onHit = onHit
        self.onExitCadenceMode = onExitCadenceMode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isCadenceModeActive: isCadenceModeActive,
            onHit: onHit,
            onExitCadenceMode: onExitCadenceMode
        )
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        let view = NSView(frame: .zero)
        context.coordinator.captureView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isCadenceModeActive = isCadenceModeActive
        context.coordinator.onHit = onHit
        context.coordinator.onExitCadenceMode = onExitCadenceMode
        context.coordinator.captureView = nsView
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var isCadenceModeActive: Bool
        var onHit: @MainActor (RhythmLane) -> Void
        var onExitCadenceMode: @MainActor () -> Void
        weak var captureView: NSView?
        private var monitor: Any?

        init(
            isCadenceModeActive: Bool,
            onHit: @escaping @MainActor (RhythmLane) -> Void,
            onExitCadenceMode: @escaping @MainActor () -> Void
        ) {
            self.isCadenceModeActive = isCadenceModeActive
            self.onHit = onHit
            self.onExitCadenceMode = onExitCadenceMode
        }

        func installMonitor() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown
            ) { [weak self] event in
                guard let self else {
                    return event
                }
                return handle(event)
            }
        }

        func removeMonitor() {
            guard let monitor else {
                return
            }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard
                let captureWindow = captureView?.window,
                event.windowNumber == captureWindow.windowNumber,
                !event.isARepeat,
                event.modifierFlags.isDisjoint(
                    with: [.command, .control, .option]
                )
            else {
                return event
            }

            let responder = captureWindow.firstResponder
            let hasEditableFirstResponder = (
                responder as? NSTextView
            )?.isEditable == true
            let isBlockedByModal = NSApp.modalWindow != nil
                || captureWindow.attachedSheet != nil
                || NSApp.mainMenu?.highlightedItem != nil

            guard let action = RhythmKeyDecision.decideAction(
                keyCode: event.keyCode,
                isNowPlayingVisible: true,
                isCadenceModeActive: isCadenceModeActive,
                hasEditableFirstResponder: hasEditableFirstResponder,
                isBlockedByModal: isBlockedByModal
            ) else {
                return event
            }

            switch action {
            case let .hit(lane):
                onHit(lane)
            case .exitCadenceMode:
                onExitCadenceMode()
            }
            return nil
        }
    }
}
