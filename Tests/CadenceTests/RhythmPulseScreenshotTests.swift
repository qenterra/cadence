import AppKit
@testable import Cadence
import SwiftUI
import Testing

@MainActor
struct RhythmPulseScreenshotTests {
    @Test("Render Rhythm Pulse across Lyrics in Light and Dark")
    func renderRhythmPulseScreenshots() async throws {
        guard FileManager.default.fileExists(atPath: Self.updateMarker.path) else {
            return
        }

        let fixture = try await DocumentationScreenshotFixture.make()
        fixture.model.presentNowPlaying()
        fixture.model.selectedNowPlayingPanel = .lyrics

        let visualQAState = RhythmPulseVisualQAState(
            palette: RhythmAccentPalette(
                colors: [
                    RhythmPulseColor(red: 0.93, green: 0.18, blue: 0.52),
                    RhythmPulseColor(red: 0.51, green: 0.25, blue: 0.98),
                    RhythmPulseColor(red: 0.03, green: 0.74, blue: 0.91),
                ]
            ),
            seed: 0xCAD34CE,
            lanes: [.left, .right, .left]
        )
        let focusLyricDocument = Self.focusLyricDocument
        let focusVisualQAState = RhythmPulseVisualQAState(
            palette: visualQAState.palette,
            seed: visualQAState.seed,
            lanes: visualQAState.lanes,
            isFocusActive: true,
            focusLyricDocument: focusLyricDocument,
            focusPresentationTime: 89
        )

        try await captureStaticStates(
            fixture: fixture,
            pulseState: visualQAState,
            focusState: focusVisualQAState
        )
        try await captureKeyboardTransition(
            fixture: fixture,
            visualQAState: RhythmPulseVisualQAState(
                palette: visualQAState.palette,
                seed: visualQAState.seed,
                lanes: [],
                focusLyricDocument: focusLyricDocument,
                focusPresentationTime: 89
            )
        )
    }

    private func captureStaticStates(
        fixture: DocumentationScreenshotFixture,
        pulseState: RhythmPulseVisualQAState,
        focusState: RhythmPulseVisualQAState
    ) async throws {
        try await fixture.capture(
            "qa-rhythm-min-dark.png",
            rhythmPulseVisualQAState: pulseState
        )
        try await fixture.capture(
            "qa-rhythm-min-light.png",
            appearance: .light,
            rhythmPulseVisualQAState: pulseState
        )
        try await fixture.capture(
            "qa-rhythm-wide-dark.png",
            contentSize: .wide,
            rhythmPulseVisualQAState: pulseState
        )
        try await fixture.capture(
            "qa-rhythm-wide-light.png",
            contentSize: .wide,
            appearance: .light,
            rhythmPulseVisualQAState: pulseState
        )
        try await fixture.capture(
            "qa-rhythm-min-focus-dark.png",
            rhythmPulseVisualQAState: focusState
        )
        try await fixture.capture(
            "qa-rhythm-min-focus-light.png",
            appearance: .light,
            rhythmPulseVisualQAState: focusState
        )
        try await fixture.capture(
            "qa-rhythm-wide-focus-dark.png",
            contentSize: .wide,
            rhythmPulseVisualQAState: focusState
        )
        try await fixture.capture(
            "qa-rhythm-wide-focus-light.png",
            contentSize: .wide,
            appearance: .light,
            rhythmPulseVisualQAState: focusState
        )
    }

    private func captureKeyboardTransition(
        fixture: DocumentationScreenshotFixture,
        visualQAState: RhythmPulseVisualQAState
    ) async throws {
        let contentSize = NSSize.wide
        let rootView = CadenceRootView(model: fixture.model)
            .frame(width: contentSize.width, height: contentSize.height)
            .environment(\.colorScheme, ColorScheme.dark)
            .environment(\.rhythmPulseVisualQAState, visualQAState)
            .tint(CadenceTheme.primaryAccent)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Cadence"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }

        try await Task.sleep(for: .milliseconds(500))
        window.makeFirstResponder(hostingView)
        sendKey(keyCode: 6, characters: "z", to: window)
        try await Task.sleep(for: .milliseconds(80))
        sendKey(keyCode: 7, characters: "x", to: window)

        try await Task.sleep(for: .milliseconds(220))
        try capture(
            window: window,
            hostingView: hostingView,
            filename: "qa-rhythm-wide-transition-mid-dark.png"
        )

        try await Task.sleep(for: .milliseconds(380))
        try capture(
            window: window,
            hostingView: hostingView,
            filename: "qa-rhythm-wide-transition-settled-dark.png"
        )
    }

    private func sendKey(
        keyCode: UInt16,
        characters: String,
        to window: NSWindow
    ) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
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

    private func capture(
        window: NSWindow,
        hostingView: NSView,
        filename: String
    ) throws {
        hostingView.layoutSubtreeIfNeeded()
        guard
            let frameView = window.contentView?.superview,
            let representation = frameView.bitmapImageRepForCachingDisplay(
                in: frameView.bounds
            )
        else {
            throw RhythmScreenshotError.captureUnavailable
        }
        frameView.cacheDisplay(in: frameView.bounds, to: representation)
        guard let data = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw RhythmScreenshotError.encodingFailed
        }
        try data.write(
            to: Self.outputDirectory.appending(path: filename),
            options: .atomic
        )
    }

    private static var updateMarker: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build/update-rhythm-screenshots")
    }

    private static var outputDirectory: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/images", directoryHint: .isDirectory)
    }

    private static var focusLyricDocument: LyricDocument {
        LyricDocument(
            trackID: UUID(),
            lines: [
                LyricLine(text: "We kept the signal low", startTime: 62),
                LyricLine(text: "While the city disappeared", startTime: 70),
                LyricLine(text: "Static blooming in the dark", startTime: 78),
                LyricLine(text: "Every frequency was clear", startTime: 86),
                LyricLine(text: "Until the morning found us", startTime: 94),
                LyricLine(text: "Past the edge of every frame", startTime: 102),
                LyricLine(text: "We were listening for silence", startTime: 110),
            ]
        )
    }
}

private enum RhythmScreenshotError: Error {
    case captureUnavailable
    case encodingFailed
}
