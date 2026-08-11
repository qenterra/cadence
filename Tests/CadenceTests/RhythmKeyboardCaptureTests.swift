import AppKit
@testable import Cadence
import SwiftUI
import Testing

struct RhythmKeyboardCaptureTests {
    @Test("Physical Z and X map independently of keyboard layout")
    func mapsVirtualKeyCodesToLanes() {
        #expect(
            RhythmKeyDecision.decide(
                keyCode: 6,
                isNowPlayingVisible: true,
                hasEditableFirstResponder: false,
                isBlockedByModal: false
            ) == .left
        )
        #expect(
            RhythmKeyDecision.decide(
                keyCode: 7,
                isNowPlayingVisible: true,
                hasEditableFirstResponder: false,
                isBlockedByModal: false
            ) == .right
        )
    }

    @Test("Capture leaves text controls and other workspaces alone")
    func captureIsScoped() {
        #expect(
            RhythmKeyDecision.decide(
                keyCode: 6,
                isNowPlayingVisible: false,
                hasEditableFirstResponder: false,
                isBlockedByModal: false
            ) == nil
        )
        #expect(
            RhythmKeyDecision.decide(
                keyCode: 6,
                isNowPlayingVisible: true,
                hasEditableFirstResponder: true,
                isBlockedByModal: false
            ) == nil
        )
        #expect(
            RhythmKeyDecision.decide(
                keyCode: 7,
                isNowPlayingVisible: true,
                hasEditableFirstResponder: false,
                isBlockedByModal: true
            ) == nil
        )
    }

    @Test("Unrelated key codes pass through")
    func unrelatedKeysPassThrough() {
        #expect(
            RhythmKeyDecision.decide(
                keyCode: 49,
                isNowPlayingVisible: true,
                hasEditableFirstResponder: false,
                isBlockedByModal: false
            ) == nil
        )
    }

    @Test("Escape exits only an active Rhythm Focus")
    func escapeIsScopedToActiveFocus() {
        #expect(
            RhythmKeyDecision.decideAction(
                keyCode: 53,
                isNowPlayingVisible: true,
                isFocusActive: true,
                hasEditableFirstResponder: false,
                isBlockedByModal: false
            ) == .exitFocus
        )
        #expect(
            RhythmKeyDecision.decideAction(
                keyCode: 53,
                isNowPlayingVisible: true,
                isFocusActive: false,
                hasEditableFirstResponder: false,
                isBlockedByModal: false
            ) == nil
        )
    }

    @MainActor
    @Test("The zero-size Now Playing capture receives a physical key event")
    func installedCaptureReceivesKeyEvent() async throws {
        let recorder = RhythmHitRecorder()
        let rootView = Color.clear
            .frame(width: 320, height: 240)
            .overlay(alignment: .topLeading) {
                RhythmKeyboardCapture { lane in
                    recorder.lanes.append(lane)
                }
                .frame(width: 0, height: 0)
            }
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }

        try await Task.sleep(for: .milliseconds(50))
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "z",
                charactersIgnoringModifiers: "z",
                isARepeat: false,
                keyCode: 6
            )
        )
        NSApp.sendEvent(event)

        #expect(recorder.lanes == [.left])
    }
}

@MainActor
private final class RhythmHitRecorder {
    var lanes: [RhythmLane] = []
}
