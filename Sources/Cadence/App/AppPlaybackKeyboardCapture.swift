import AppKit
import SwiftUI

enum AppPlaybackKeyDecision {
    static func shouldHandle(
        eventType: NSEvent.EventType,
        keyCode: UInt16,
        isRepeat: Bool,
        modifiers: NSEvent.ModifierFlags,
        focus: AppCommandFocus,
        isLocallyOwned: Bool = false
    ) -> Bool {
        let blockedModifiers: NSEvent.ModifierFlags = [
            .command,
            .control,
            .option,
            .shift,
        ]
        return eventType == .keyDown
            && keyCode == 49
            && !isRepeat
            && modifiers.isDisjoint(with: blockedModifiers)
            && !focus.blocksGlobalPlayback
            && !isLocallyOwned
    }

    @MainActor
    static func focus(
        in window: NSWindow,
        application: NSApplication = .shared
    ) -> AppCommandFocus {
        if application.mainMenu?.highlightedItem != nil {
            return .menu
        }
        if application.modalWindow != nil || window.attachedSheet != nil {
            return .sheet
        }
        guard let responder = window.firstResponder else {
            return .none
        }
        if responder is TrackTableView {
            return .trackTable
        }
        if let textView = responder as? NSTextView, textView.isEditable {
            return .textEditing
        }
        if responder is NSControl {
            return .localControl
        }
        return .none
    }
}

struct AppPlaybackKeyboardCapture: NSViewRepresentable {
    let isLocallyOwned: Bool
    let onToggle: @MainActor (AppCommandFocus) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isLocallyOwned: isLocallyOwned,
            onToggle: onToggle
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.captureView = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isLocallyOwned = isLocallyOwned
        context.coordinator.onToggle = onToggle
        context.coordinator.captureView = nsView
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var isLocallyOwned: Bool
        var onToggle: @MainActor (AppCommandFocus) -> Void
        weak var captureView: NSView?
        private var monitor: Any?

        init(
            isLocallyOwned: Bool,
            onToggle: @escaping @MainActor (AppCommandFocus) -> Void
        ) {
            self.isLocallyOwned = isLocallyOwned
            self.onToggle = onToggle
        }

        func installMonitor() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown
            ) { [weak self] event in
                self?.handle(event) ?? event
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
                event.window == nil || event.window === captureWindow
            else {
                return event
            }
            let focus = AppPlaybackKeyDecision.focus(in: captureWindow)
            guard AppPlaybackKeyDecision.shouldHandle(
                eventType: event.type,
                keyCode: event.keyCode,
                isRepeat: event.isARepeat,
                modifiers: event.modifierFlags,
                focus: focus,
                isLocallyOwned: isLocallyOwned
            ) else {
                return event
            }
            onToggle(focus)
            return nil
        }
    }
}
