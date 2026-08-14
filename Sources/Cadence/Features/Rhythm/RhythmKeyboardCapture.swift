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
        canActivateCadenceMode: Bool = true,
        isNowPlayingVisible _: Bool,
        isCadenceModeActive: Bool,
        hasEditableFirstResponder: Bool,
        isBlockedByModal: Bool
    ) -> RhythmKeyAction? {
        guard
            !hasEditableFirstResponder,
            !isBlockedByModal
        else {
            return nil
        }

        switch keyCode {
        case 6 where isCadenceModeActive || canActivateCadenceMode:
            return .hit(.left)
        case 7 where isCadenceModeActive || canActivateCadenceMode:
            return .hit(.right)
        case 53 where isCadenceModeActive:
            return .exitCadenceMode
        default:
            return nil
        }
    }

    static func lane(for keyCode: UInt16) -> RhythmLane? {
        switch keyCode {
        case 6:
            .left
        case 7:
            .right
        default:
            nil
        }
    }
}

struct RhythmKeyboardCapture: NSViewRepresentable {
    let canActivateCadenceMode: Bool
    let isCadenceModeActive: @MainActor () -> Bool
    let onKeyDown: @MainActor (RhythmLane) -> Void
    let onKeyUp: @MainActor (RhythmLane) -> Void
    let onExitCadenceMode: @MainActor () -> Void
    let onReleaseAllKeys: @MainActor () -> Void

    init(
        canActivateCadenceMode: Bool = true,
        isCadenceModeActive: @escaping @MainActor () -> Bool = { false },
        onKeyDown: @escaping @MainActor (RhythmLane) -> Void,
        onKeyUp: @escaping @MainActor (RhythmLane) -> Void = { _ in },
        onExitCadenceMode: @escaping @MainActor () -> Void = {},
        onReleaseAllKeys: @escaping @MainActor () -> Void = {}
    ) {
        self.canActivateCadenceMode = canActivateCadenceMode
        self.isCadenceModeActive = isCadenceModeActive
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onExitCadenceMode = onExitCadenceMode
        self.onReleaseAllKeys = onReleaseAllKeys
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            canActivateCadenceMode: canActivateCadenceMode,
            isCadenceModeActive: isCadenceModeActive,
            onKeyDown: onKeyDown,
            onKeyUp: onKeyUp,
            onExitCadenceMode: onExitCadenceMode,
            onReleaseAllKeys: onReleaseAllKeys
        )
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        let view = NSView(frame: .zero)
        context.coordinator.captureView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.canActivateCadenceMode = canActivateCadenceMode
        context.coordinator.isCadenceModeActive = isCadenceModeActive
        context.coordinator.onKeyDown = onKeyDown
        context.coordinator.onKeyUp = onKeyUp
        context.coordinator.onExitCadenceMode = onExitCadenceMode
        context.coordinator.onReleaseAllKeys = onReleaseAllKeys
        context.coordinator.captureView = nsView
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator: NSObject {
        var canActivateCadenceMode: Bool
        var isCadenceModeActive: @MainActor () -> Bool
        var onKeyDown: @MainActor (RhythmLane) -> Void
        var onKeyUp: @MainActor (RhythmLane) -> Void
        var onExitCadenceMode: @MainActor () -> Void
        var onReleaseAllKeys: @MainActor () -> Void
        weak var captureView: NSView?
        private var monitor: Any?
        private var ownedKeyCodes: Set<UInt16> = []

        init(
            canActivateCadenceMode: Bool,
            isCadenceModeActive: @escaping @MainActor () -> Bool,
            onKeyDown: @escaping @MainActor (RhythmLane) -> Void,
            onKeyUp: @escaping @MainActor (RhythmLane) -> Void,
            onExitCadenceMode: @escaping @MainActor () -> Void,
            onReleaseAllKeys: @escaping @MainActor () -> Void
        ) {
            self.canActivateCadenceMode = canActivateCadenceMode
            self.isCadenceModeActive = isCadenceModeActive
            self.onKeyDown = onKeyDown
            self.onKeyUp = onKeyUp
            self.onExitCadenceMode = onExitCadenceMode
            self.onReleaseAllKeys = onReleaseAllKeys
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func installMonitor() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .keyUp]
            ) { [weak self] event in
                guard let self else {
                    return event
                }
                return handle(event)
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidResignActive),
                name: NSApplication.didResignActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification,
                object: nil
            )
        }

        func removeMonitor() {
            guard let monitor else {
                return
            }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            releaseOwnedKeys()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard
                let captureWindow = captureView?.window,
                event.windowNumber == captureWindow.windowNumber,
                event.window == nil || event.window === captureWindow
            else {
                return event
            }

            if event.type == .keyUp,
               ownedKeyCodes.remove(event.keyCode) != nil,
               let lane = RhythmKeyDecision.lane(for: event.keyCode) {
                onKeyUp(lane)
                return nil
            }
            if event.isARepeat, ownedKeyCodes.contains(event.keyCode) {
                return nil
            }
            guard
                event.type == .keyDown,
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
                canActivateCadenceMode: canActivateCadenceMode,
                isNowPlayingVisible: true,
                isCadenceModeActive: isCadenceModeActive(),
                hasEditableFirstResponder: hasEditableFirstResponder,
                isBlockedByModal: isBlockedByModal
            ) else {
                return event
            }

            switch action {
            case let .hit(lane):
                ownedKeyCodes.insert(event.keyCode)
                onKeyDown(lane)
            case .exitCadenceMode:
                onExitCadenceMode()
            }
            return nil
        }

        @objc private func applicationDidResignActive() {
            releaseOwnedKeys()
        }

        @objc private func windowDidResignKey(_ notification: Notification) {
            guard notification.object as? NSWindow === captureView?.window else {
                return
            }
            releaseOwnedKeys()
        }

        private func releaseOwnedKeys() {
            for keyCode in ownedKeyCodes.sorted() {
                guard let lane = RhythmKeyDecision.lane(for: keyCode) else {
                    continue
                }
                onKeyUp(lane)
            }
            ownedKeyCodes.removeAll(keepingCapacity: true)
            onReleaseAllKeys()
        }
    }
}
