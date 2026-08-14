import AppKit
@testable import Cadence
import SwiftUI
import Testing

@MainActor
struct CadenceModeScreenshotTests {
    private struct VisualQAStates {
        let standard: RhythmPulseVisualQAState
        let cadenceMode: RhythmPulseVisualQAState
        let grayscale: RhythmPulseVisualQAState
        let entry: RhythmPulseVisualQAState
    }

    @Test("Render Cadence Mode, its entry, and the inactive hint")
    func renderCadenceModeScreenshots() async throws {
        guard FileManager.default.fileExists(atPath: Self.updateMarker.path) else {
            return
        }

        let fixture = try await DocumentationScreenshotFixture.make()
        fixture.model.presentNowPlaying()
        fixture.model.selectedNowPlayingPanel = .lyrics

        let states = Self.makeVisualQAStates()

        try await captureStaticStates(
            fixture: fixture,
            standardState: states.standard,
            cadenceModeState: states.cadenceMode,
            grayscaleState: states.grayscale
        )
        let transitionFixture = try await DocumentationScreenshotFixture.make()
        try await captureKeyboardTransition(
            fixture: transitionFixture,
            visualQAState: states.entry
        )
    }
}

private extension CadenceModeScreenshotTests {
    private static func makeVisualQAStates() -> VisualQAStates {
        let standard = RhythmPulseVisualQAState(
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
        let cadenceMode = RhythmPulseVisualQAState(
            palette: standard.palette,
            seed: standard.seed,
            lanes: standard.lanes,
            isCadenceModeActive: true,
            cadenceModeLyricDocument: cadenceModeLyricDocument,
            cadenceModePresentationTime: 89
        )
        let grayscale = RhythmPulseVisualQAState(
            palette: RhythmAccentPalette(
                colors: [
                    RhythmPulseColor(red: 0.4, green: 0.4, blue: 0.4),
                    RhythmPulseColor(red: 0.7, green: 0.7, blue: 0.7),
                ]
            ),
            seed: 0x6A4A,
            lanes: [.left, .right],
            isCadenceModeActive: true,
            cadenceModeLyricDocument: cadenceModeLyricDocument,
            cadenceModePresentationTime: 89
        )

        return VisualQAStates(
            standard: standard,
            cadenceMode: cadenceMode,
            grayscale: grayscale,
            entry: RhythmPulseVisualQAState(
                palette: standard.palette,
                seed: standard.seed,
                lanes: [],
                cadenceModeLyricDocument: cadenceModeLyricDocument,
                cadenceModePresentationTime: 89
            )
        )
    }

    private func captureStaticStates(
        fixture: DocumentationScreenshotFixture,
        standardState: RhythmPulseVisualQAState,
        cadenceModeState: RhythmPulseVisualQAState,
        grayscaleState: RhythmPulseVisualQAState
    ) async throws {
        try await fixture.capture(
            "qa-cadence-mode-standard-min-dark.png",
            rhythmPulseVisualQAState: standardState
        )
        try await fixture.capture(
            "qa-cadence-mode-standard-min-light.png",
            appearance: .light,
            rhythmPulseVisualQAState: standardState
        )
        try await fixture.capture(
            "qa-cadence-mode-min-dark.png",
            rhythmPulseVisualQAState: cadenceModeState
        )
        try await fixture.capture(
            "qa-cadence-mode-min-light.png",
            appearance: .light,
            rhythmPulseVisualQAState: cadenceModeState
        )
        try await fixture.capture(
            "qa-cadence-mode-wide-dark.png",
            contentSize: .wide,
            rhythmPulseVisualQAState: cadenceModeState
        )
        try await fixture.capture(
            "qa-cadence-mode-wide-light.png",
            contentSize: .wide,
            appearance: .light,
            rhythmPulseVisualQAState: cadenceModeState
        )
        try await fixture.capture(
            "qa-cadence-mode-large-dark.png",
            contentSize: .large,
            rhythmPulseVisualQAState: cadenceModeState
        )
        try await fixture.capture(
            "qa-cadence-mode-grayscale-min-dark.png",
            rhythmPulseVisualQAState: grayscaleState
        )
    }

    private func captureKeyboardTransition(
        fixture: DocumentationScreenshotFixture,
        visualQAState: RhythmPulseVisualQAState
    ) async throws {
        fixture.model.dismissNowPlaying()
        let cadenceModeSession = CadenceModeSession(automatesTiming: false)
        let transition = makeTransitionWindow(
            model: fixture.model,
            session: cadenceModeSession,
            visualQAState: visualQAState
        )
        let window = transition.window
        let hostingView = transition.hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }

        try await Task.sleep(for: .milliseconds(500))
        window.makeFirstResponder(hostingView)
        sendKey(type: .keyDown, keyCode: 6, characters: "z", to: window)
        try await Task.sleep(for: .milliseconds(80))
        sendKey(type: .keyDown, keyCode: 7, characters: "x", to: window)

        try await Task.sleep(for: .milliseconds(260))
        try capture(
            window: window,
            hostingView: hostingView,
            filename: "qa-cadence-mode-wide-transition-mid-dark.png"
        )

        guard cadenceModeSession.isActive else {
            throw CadenceModeScreenshotError.presentationDidNotActivate
        }
        try await Task.sleep(for: .milliseconds(300))
        sendKey(type: .keyUp, keyCode: 6, characters: "z", to: window)
        sendKey(type: .keyUp, keyCode: 7, characters: "x", to: window)
        sendKey(type: .keyDown, keyCode: 6, characters: "z", to: window)
        try await Task.sleep(for: .milliseconds(120))
        guard !cadenceModeSession.pulseStore.renderParticles.isEmpty,
              !cadenceModeSession.pulseStore.renderWashes.isEmpty else {
            throw CadenceModeScreenshotError.pulseDidNotRender
        }
        try capture(
            window: window,
            hostingView: hostingView,
            filename: "qa-cadence-mode-wide-transition-settled-dark.png"
        )
        sendKey(type: .keyUp, keyCode: 6, characters: "z", to: window)
    }

    private func makeTransitionWindow(
        model: CadenceAppModel,
        session: CadenceModeSession,
        visualQAState: RhythmPulseVisualQAState
    ) -> (window: NSWindow, hostingView: NSView) {
        let contentSize = NSSize.wide
        let rootView = CadenceRootView(model: model, cadenceModeSession: session)
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
        return (window, hostingView)
    }

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

    private func capture(
        window: NSWindow,
        hostingView _: NSView,
        filename: String
    ) throws {
        guard
            let frameView = window.contentView?.superview,
            let representation = frameView.bitmapImageRepForCachingDisplay(
                in: frameView.bounds
            )
        else {
            throw CadenceModeScreenshotError.captureUnavailable
        }
        frameView.cacheDisplay(in: frameView.bounds, to: representation)
        guard let data = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw CadenceModeScreenshotError.encodingFailed
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
            .appending(path: ".build/update-cadence-mode-screenshots")
    }

    private static var outputDirectory: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/images", directoryHint: .isDirectory)
    }

    private static var cadenceModeLyricDocument: LyricDocument {
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

private enum CadenceModeScreenshotError: Error {
    case captureUnavailable
    case encodingFailed
    case presentationDidNotActivate
    case pulseDidNotRender
}
