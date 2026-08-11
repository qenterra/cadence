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

    @Test("Physical Cadence keys work outside Now Playing")
    func captureIsGlobal() {
        #expect(
            RhythmKeyDecision.decide(
                keyCode: 6,
                isNowPlayingVisible: false,
                hasEditableFirstResponder: false,
                isBlockedByModal: false
            ) == .left
        )
    }

    @Test("Capture leaves text controls and modal workspaces alone")
    func captureIsScoped() {
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

    @Test("Cadence keys pass through while playback is unavailable")
    func unavailablePlaybackPassesThrough() {
        #expect(
            RhythmKeyDecision.decideAction(
                keyCode: 6,
                canActivateCadenceMode: false,
                isNowPlayingVisible: false,
                isCadenceModeActive: false,
                hasEditableFirstResponder: false,
                isBlockedByModal: false
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

    @Test("Escape exits only an active Cadence Mode")
    func escapeIsScopedToActiveCadenceMode() {
        #expect(
            RhythmKeyDecision.decideAction(
                keyCode: 53,
                isNowPlayingVisible: true,
                isCadenceModeActive: true,
                hasEditableFirstResponder: false,
                isBlockedByModal: false
            ) == .exitCadenceMode
        )
        #expect(
            RhythmKeyDecision.decideAction(
                keyCode: 53,
                isNowPlayingVisible: true,
                isCadenceModeActive: false,
                hasEditableFirstResponder: false,
                isBlockedByModal: false
            ) == nil
        )
    }

    @MainActor
    @Test("The root capture receives physical key down and key up events")
    func installedCaptureReceivesKeyLifecycle() async throws {
        let recorder = RhythmHitRecorder()
        let rootView = Color.clear
            .frame(width: 320, height: 240)
            .overlay(alignment: .topLeading) {
                RhythmKeyboardCapture(
                    canActivateCadenceMode: true
                ) { lane in
                    recorder.pressedLanes.append(lane)
                } onKeyUp: { lane in
                    recorder.releasedLanes.append(lane)
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
        let keyDown = try #require(
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
        let keyUp = try #require(
            NSEvent.keyEvent(
                with: .keyUp,
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
        NSApp.sendEvent(keyDown)
        NSApp.sendEvent(keyUp)

        #expect(recorder.pressedLanes == [.left])
        #expect(recorder.releasedLanes == [.left])
    }

    @MainActor
    @Test("A global chord presents Cadence Mode and track changes keep it active")
    func globalChordAndTrackChangeLifecycle() async throws {
        let fixture = try await DocumentationScreenshotFixture.make()
        fixture.model.playbackWorkspace = .hidden
        let session = CadenceModeSession(automatesTiming: false)
        let contentSize = NSSize(width: 1200, height: 760)
        let hostingView = NSHostingView(
            rootView: CadenceRootView(
                model: fixture.model,
                cadenceModeSession: session
            )
            .frame(width: contentSize.width, height: contentSize.height)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable],
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

        try await Task.sleep(for: .milliseconds(80))
        window.makeFirstResponder(hostingView)
        sendKey(
            type: .keyDown,
            keyCode: 6,
            characters: "z",
            to: window
        )
        sendKey(
            type: .keyDown,
            keyCode: 7,
            characters: "x",
            to: window
        )
        try await Task.sleep(for: .milliseconds(80))

        #expect(fixture.model.playbackWorkspace == .nowPlaying)
        #expect(session.isActive)

        let previousTrackID = fixture.model.currentPlaybackTrack?.id
        fixture.model.selectNextTrack()
        for _ in 0 ..< 20 where
            fixture.model.currentPlaybackTrack?.id == previousTrackID {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(fixture.model.currentPlaybackTrack?.id != previousTrackID)
        #expect(fixture.model.playbackWorkspace == .nowPlaying)
        #expect(session.isActive)

        sendKey(
            type: .keyUp,
            keyCode: 6,
            characters: "z",
            to: window
        )
        sendKey(
            type: .keyUp,
            keyCode: 7,
            characters: "x",
            to: window
        )
    }

    @MainActor
    private func sendKey(
        type: NSEvent.EventType,
        keyCode: UInt16,
        characters: String,
        to window: NSWindow
    ) {
        guard let event = NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            return
        }
        NSApp.sendEvent(event)
    }
}

@MainActor
private final class RhythmHitRecorder {
    var pressedLanes: [RhythmLane] = []
    var releasedLanes: [RhythmLane] = []
}
