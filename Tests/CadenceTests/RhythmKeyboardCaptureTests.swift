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

    @Test("Cadence keys pass through only when no playback item is loaded")
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
}

struct RhythmKeyboardCaptureLifecycleTests {
    @MainActor
    @Test(
        "A paused global chord presents Cadence and post-transition keys emit",
        .appKitExclusive
    )
    func globalChordAndTrackChangeLifecycle() async throws {
        let fixture = try await DocumentationScreenshotFixture.make()
        fixture.model.isPlaying = false
        #expect(fixture.model.hasCurrentPlaybackItem)
        #expect(!fixture.model.isPlaying)
        fixture.model.playbackWorkspace = .hidden
        let session = CadenceModeSession(automatesTiming: false)
        let (window, hostingView) = makeCadenceWindow(
            model: fixture.model,
            session: session
        )
        defer { close(window) }

        try await activateCadenceMode(
            in: window,
            hostingView: hostingView,
            model: fixture.model,
            session: session
        )
        try await verifyPulseEmission(in: window, session: session)
        try await verifyTrackChangePreservesMode(
            model: fixture.model,
            session: session
        )
    }

    @MainActor
    private func makeCadenceWindow(
        model: CadenceAppModel,
        session: CadenceModeSession
    ) -> (NSWindow, NSView) {
        let contentSize = NSSize(width: 1200, height: 760)
        let hostingView = NSHostingView(
            rootView: CadenceRootView(model: model, cadenceModeSession: session)
                .frame(width: contentSize.width, height: contentSize.height)
        )
        let window = makeWindow(
            contentView: hostingView,
            contentSize: contentSize,
            styleMask: [.titled, .closable, .resizable]
        )
        return (window, hostingView)
    }

    @MainActor
    private func makeWindow(
        contentView: NSView,
        contentSize: NSSize,
        styleMask: NSWindow.StyleMask
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        return window
    }

    @MainActor
    private func activateCadenceMode(
        in window: NSWindow,
        hostingView: NSView,
        model: CadenceAppModel,
        session: CadenceModeSession
    ) async throws {
        try await Task.sleep(for: .milliseconds(80))
        window.makeFirstResponder(hostingView)
        sendKey(type: .keyDown, keyCode: 6, characters: "z", to: window)
        sendKey(type: .keyDown, keyCode: 7, characters: "x", to: window)

        #expect(model.playbackWorkspace == .nowPlaying)
        #expect(session.activationIsPending)
        #expect(!session.isActive)
        try await waitUntil { session.isActive }
        #expect(model.playbackWorkspace == .nowPlaying)
        #expect(session.isActive)
        #expect(!model.isPlaying)
        try await waitUntil { session.pulseStore.hasAttachedCompositor }
        #expect(session.pulseStore.hasAttachedCompositor)
    }

    @MainActor
    private func verifyPulseEmission(
        in window: NSWindow,
        session: CadenceModeSession
    ) async throws {
        sendKey(type: .keyUp, keyCode: 6, characters: "z", to: window)
        sendKey(type: .keyUp, keyCode: 7, characters: "x", to: window)
        sendKey(type: .keyDown, keyCode: 6, characters: "z", to: window)
        sendKey(type: .keyUp, keyCode: 6, characters: "z", to: window)
        try await Task.sleep(for: .milliseconds(40))

        #expect(!session.pulseStore.renderParticles.isEmpty)
        #expect(!session.pulseStore.renderWashes.isEmpty)
        try await waitUntil {
            session.pulseStore.visibleCompositorEffectCount > 0
        }
        #expect(session.pulseStore.visibleCompositorEffectCount > 0)
    }

    @MainActor
    private func verifyTrackChangePreservesMode(
        model: CadenceAppModel,
        session: CadenceModeSession
    ) async throws {
        let previousTrackID = model.currentPlaybackTrack?.id
        model.selectNextTrack()
        try await waitUntil { model.currentPlaybackTrack?.id != previousTrackID }

        #expect(model.currentPlaybackTrack?.id != previousTrackID)
        #expect(model.playbackWorkspace == .nowPlaying)
        #expect(session.isActive)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition() {
            guard clock.now < deadline else {
                throw RhythmKeyboardCaptureTestError.timedOut
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    private func close(_ window: NSWindow) {
        window.orderOut(nil)
        window.close()
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

private enum RhythmKeyboardCaptureTestError: Error {
    case timedOut
}
