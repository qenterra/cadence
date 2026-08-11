import AppKit
import SwiftUI

enum RhythmKeyAction: Equatable {
    case hit(RhythmLane)
    case exitFocus
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
            isFocusActive: false,
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
        isFocusActive: Bool,
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
        case 53 where isFocusActive:
            return .exitFocus
        default:
            return nil
        }
    }
}

struct RhythmKeyboardCapture: NSViewRepresentable {
    let isFocusActive: Bool
    let onHit: @MainActor (RhythmLane) -> Void
    let onExitFocus: @MainActor () -> Void

    init(
        isFocusActive: Bool = false,
        onHit: @escaping @MainActor (RhythmLane) -> Void,
        onExitFocus: @escaping @MainActor () -> Void = {}
    ) {
        self.isFocusActive = isFocusActive
        self.onHit = onHit
        self.onExitFocus = onExitFocus
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isFocusActive: isFocusActive,
            onHit: onHit,
            onExitFocus: onExitFocus
        )
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        let view = NSView(frame: .zero)
        context.coordinator.captureView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isFocusActive = isFocusActive
        context.coordinator.onHit = onHit
        context.coordinator.onExitFocus = onExitFocus
        context.coordinator.captureView = nsView
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var isFocusActive: Bool
        var onHit: @MainActor (RhythmLane) -> Void
        var onExitFocus: @MainActor () -> Void
        weak var captureView: NSView?
        private var monitor: Any?

        init(
            isFocusActive: Bool,
            onHit: @escaping @MainActor (RhythmLane) -> Void,
            onExitFocus: @escaping @MainActor () -> Void
        ) {
            self.isFocusActive = isFocusActive
            self.onHit = onHit
            self.onExitFocus = onExitFocus
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
                isFocusActive: isFocusActive,
                hasEditableFirstResponder: hasEditableFirstResponder,
                isBlockedByModal: isBlockedByModal
            ) else {
                return event
            }

            switch action {
            case let .hit(lane):
                onHit(lane)
            case .exitFocus:
                onExitFocus()
            }
            return nil
        }
    }
}
