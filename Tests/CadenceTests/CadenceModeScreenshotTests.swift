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
            cadenceModePresentationTime: 89,
            cadenceModeBassLevel: 0.9
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
            cadenceModePresentationTime: 89,
            cadenceModeBassLevel: 0.65
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
                cadenceModePresentationTime: 89,
                cadenceModeBassLevel: 0.9
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

enum CadenceModeScreenshotError: Error {
    case captureUnavailable
    case encodingFailed
    case pixelConversionFailed
    case presentationDidNotActivate
    case pulseDidNotRender
    case visualReadinessTimedOut
}

@MainActor
struct CadenceModeLyricsVisualTests {
    @Test(
        "Record normal and Reduce Motion synchronized lyrics",
        .appKitExclusive
    )
    func recordsNormalAndReducedMotionActuals() async throws {
        let navigationPreferences = NavigationScreenshotPreferences()
        navigationPreferences.install()
        defer { navigationPreferences.restore() }

        let fixture = try await DocumentationScreenshotFixture.make()
        do {
            fixture.model.presentNowPlaying()
            fixture.model.selectedNowPlayingPanel = .lyrics
            let trackID = try #require(fixture.model.currentPlaybackTrack?.id)
            let document = Self.synchronizedDocument(trackID: trackID)
            let activeLineID = SynchronizedLyricTimeline(document: document)
                .activeLineID(at: 89)
            let expectedActiveLineID = Self.lyricLineID(4)
            let activeAppearance = ProductionLyricLineAppearance.resolve(
                isActive: true,
                isSynchronized: true
            )
            let inactiveAppearance = ProductionLyricLineAppearance.resolve(
                isActive: false,
                isSynchronized: true
            )
            let normalMotion = LyricMotionBehavior.resolve(
                reduceMotion: false
            )
            let reducedMotion = LyricMotionBehavior.resolve(
                reduceMotion: true
            )

            #expect(fixture.model.playbackWorkspace == .nowPlaying)
            #expect(fixture.model.selectedNowPlayingPanel == .lyrics)
            #expect(document.trackID == .managed(trackID))
            #expect(document.timingStatus == .synchronized)
            #expect(activeLineID == expectedActiveLineID)
            #expect(activeAppearance.tone == .primary)
            #expect(activeAppearance.opacity == 1)
            #expect(!activeAppearance.usesShimmer)
            #expect(inactiveAppearance.tone == .secondary)
            #expect(inactiveAppearance.opacity == 0.58)
            #expect(!inactiveAppearance.usesShimmer)
            #expect(normalMotion.animatesEmphasis)
            #expect(normalMotion.animatesScroll)
            #expect(!reducedMotion.animatesEmphasis)
            #expect(!reducedMotion.animatesScroll)

            let visualQAState = RhythmPulseVisualQAState(
                palette: RhythmAccentPalette(
                    colors: [
                        RhythmPulseColor(red: 0.93, green: 0.18, blue: 0.52),
                        RhythmPulseColor(red: 0.51, green: 0.25, blue: 0.98),
                        RhythmPulseColor(red: 0.03, green: 0.74, blue: 0.91),
                    ]
                ),
                seed: 0xCAD34CE,
                lanes: [.left, .right, .left],
                isCadenceModeActive: true,
                cadenceModeLyricDocument: document,
                cadenceModePresentationTime: 89,
                cadenceModeBassLevel: 0
            )
            let normal = try await CadenceModeRecordsOnlyRenderer.capture(
                fixture: fixture,
                visualQAState: visualQAState,
                reduceMotion: false,
                filename: "task-3-synchronized-lyrics-normal.png"
            )
            let reduced = try await CadenceModeRecordsOnlyRenderer.capture(
                fixture: fixture,
                visualQAState: visualQAState,
                reduceMotion: true,
                filename: "task-3-synchronized-lyrics-reduce-motion.png"
            )

            #expect(normal.contentSize == .minimum)
            #expect(reduced.contentSize == .minimum)
            #expect(normal.pixelWidth == normal.expectedPixelWidth)
            #expect(normal.pixelHeight == normal.expectedPixelHeight)
            #expect(reduced.pixelWidth == reduced.expectedPixelWidth)
            #expect(reduced.pixelHeight == reduced.expectedPixelHeight)
            #expect(normal.pixelWidth == reduced.pixelWidth)
            #expect(normal.pixelHeight == reduced.pixelHeight)
            #expect(normal.byteCount > 0)
            #expect(reduced.byteCount > 0)

            try await fixture.cleanup()
        } catch {
            try? await fixture.cleanup()
            throw error
        }
    }
}

@MainActor
struct CadenceModeBassVisualTests {
    @Test(
        "Record silence, high bass, and Reduce Motion artwork actuals",
        .appKitExclusive
    )
    func recordsBassArtworkActuals() async throws {
        let navigationPreferences = NavigationScreenshotPreferences()
        navigationPreferences.install()
        defer { navigationPreferences.restore() }

        let fixture = try await DocumentationScreenshotFixture.make()
        do {
            fixture.model.presentNowPlaying()
            fixture.model.selectedNowPlayingPanel = .lyrics
            let trackID = try #require(fixture.model.currentPlaybackTrack?.id)
            let coordinator = try #require(fixture.model.playbackCoordinator)
            let backend = try #require(
                coordinator.activeBackend as? PlaybackTestBackend
            )
            let document = bassVisualDocument(trackID: trackID)
            let visualQAState = visualQAState(document: document)

            fixture.model.isPlaying = true
            backend.emit(.time(89))
            backend.bassMeter.store(0)
            #expect(fixture.model.playbackBassLevel == 0)
            #expect(visualQAState.cadenceModeBassLevel == nil)

            let silence = try await CadenceModeRecordsOnlyRenderer.capture(
                fixture: fixture,
                visualQAState: visualQAState,
                reduceMotion: false,
                filename: "task-4-cadence-mode-bass-silence.png"
            )

            backend.bassMeter.store(1)
            #expect(fixture.model.playbackBassLevel == 1)
            let highBass = try await CadenceModeRecordsOnlyRenderer.capture(
                fixture: fixture,
                visualQAState: visualQAState,
                reduceMotion: false,
                filename: "task-4-cadence-mode-bass-high.png",
                expectedArtworkScale: 1.02 ... 1.05
            )
            let reduced = try await CadenceModeRecordsOnlyRenderer.capture(
                fixture: fixture,
                visualQAState: visualQAState,
                reduceMotion: true,
                filename: "task-4-cadence-mode-bass-reduce-motion.png"
            )
            try assertVisualAcceptance(
                silence: silence,
                highBass: highBass,
                reduced: reduced
            )

            try await fixture.cleanup()
        } catch {
            try? await fixture.cleanup()
            throw error
        }
    }

    @Test(
        "A mounted Cadence hierarchy drops predecessor bass on gapless adoption",
        .appKitExclusive
    )
    func gaplessSuccessorFirstRenderStartsAtIdentityScale() async throws {
        let navigationPreferences = NavigationScreenshotPreferences()
        navigationPreferences.install()
        defer { navigationPreferences.restore() }

        let fixture = try await DocumentationScreenshotFixture.make()
        do {
            fixture.model.presentNowPlaying()
            fixture.model.selectedNowPlayingPanel = .lyrics
            let coordinator = try #require(fixture.model.playbackCoordinator)
            let backend = try #require(
                coordinator.activeBackend as? PlaybackTestBackend
            )
            let firstTrackID = try #require(
                coordinator.state.currentTrack?.id
            )
            let successorTrackID = try #require(
                coordinator.state.queue?.upNextTrackIDs.first
            )
            let document = bassVisualDocument(trackID: firstTrackID)
            let visualReadiness = CadenceModeVisualReadinessTracker()
            let contentSize = NSSize.minimum

            fixture.model.isPlaying = true
            backend.bassMeter.store(1)
            #expect(fixture.model.playbackBassLevel == 1)

            let rootView = CadenceRootView(model: fixture.model)
                .frame(width: contentSize.width, height: contentSize.height)
                .environment(\.colorScheme, .dark)
                .environment(
                    \.cadenceModeVisualQABackgroundReduceMotionOverride,
                    true
                )
                .environment(
                    \.cadenceModeVisualQAReduceMotionOverride,
                    false
                )
                .environment(
                    \.cadenceModeVisualReadinessObserver,
                    visualReadiness.observer
                )
                .environment(
                    \.rhythmPulseVisualQAState,
                    visualQAState(document: document)
                )
                .defaultAppStorage(
                    DocumentationScreenshotDefaults.userDefaults
                )
                .environment(\.visualRegressionHidesPreviewChrome, true)
                .tint(CadenceTheme.primaryAccent)
            let hostingView = NSHostingView(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hostingView
            window.contentMinSize = contentSize
            window.contentMaxSize = contentSize
            window.setContentSize(contentSize)
            window.makeKeyAndOrderFront(nil)
            defer {
                window.orderOut(nil)
                window.close()
            }

            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            _ = try await visualReadiness.waitUntilReady(
                trackID: firstTrackID,
                expectedArtworkScale: 1.02 ... 1.05
            )

            backend.emit(
                .finished(
                    trackID: firstTrackID,
                    successorStarted: successorTrackID
                )
            )
            let successorSnapshot = try await visualReadiness
                .waitForFirstAcceptedRender(trackID: successorTrackID)

            #expect(coordinator.state.currentTrack?.id == successorTrackID)
            #expect(successorSnapshot.artworkScale == 1)

            try await fixture.cleanup()
        } catch {
            try? await fixture.cleanup()
            throw error
        }
    }

    private func assertVisualAcceptance(
        silence: CadenceModeRecordsOnlyCapture,
        highBass: CadenceModeRecordsOnlyCapture,
        reduced: CadenceModeRecordsOnlyCapture
    ) throws {
        let silenceResponse = CadenceModeBassResponse.resolve(
            level: 0,
            reduceMotion: false
        )
        let highBassResponse = CadenceModeBassResponse.resolve(
            level: 1,
            reduceMotion: false
        )
        let reducedResponse = CadenceModeBassResponse.resolve(
            level: 1,
            reduceMotion: true
        )
        #expect(silenceResponse == .identity)
        #expect(highBassResponse.artworkScale > 1)
        #expect(highBassResponse.artworkScale <= 1.05)
        #expect(reducedResponse == .identity)
        #expect(silence.contentSize == .minimum)
        #expect(highBass.contentSize == .minimum)
        #expect(reduced.contentSize == .minimum)
        #expect(silence.pixelWidth == silence.expectedPixelWidth)
        #expect(silence.pixelHeight == silence.expectedPixelHeight)
        #expect(highBass.pixelWidth == silence.pixelWidth)
        #expect(highBass.pixelHeight == silence.pixelHeight)
        #expect(reduced.pixelWidth == silence.pixelWidth)
        #expect(reduced.pixelHeight == silence.pixelHeight)
        #expect(silence.byteCount > 0)
        #expect(highBass.byteCount > 0)
        #expect(reduced.byteCount > 0)
        #expect(silence.artworkScale == 1)
        #expect(highBass.artworkScale > 1)
        #expect(highBass.artworkScale <= 1.05)
        #expect(reduced.artworkScale == 1)
        #expect(!silence.hasSamePNG(as: highBass))
        #expect(silence.hasSamePNG(as: reduced))
        #expect(silence.hasSamePixels(as: reduced))
        try assertArtworkOnlyDifference(silence: silence, highBass: highBass)
    }

    private func assertArtworkOnlyDifference(
        silence: CadenceModeRecordsOnlyCapture,
        highBass: CadenceModeRecordsOnlyCapture
    ) throws {
        let difference = try #require(
            silence.pixelDifferenceBounds(comparedTo: highBass)
        )
        let artworkFrame = silence.artworkFrame.union(highBass.artworkFrame)
        let artworkRegion = CGRect(
            x: artworkFrame.minX - 72,
            y: artworkFrame.minY - 128,
            width: artworkFrame.width + 144,
            height: artworkFrame.height + 176
        )
        let topDownRegion = silence.pixelRect(
            for: artworkRegion,
            verticallyFlipped: false
        )
        let bottomUpRegion = silence.pixelRect(
            for: artworkRegion,
            verticallyFlipped: true
        )
        #expect(
            topDownRegion.contains(difference)
                || bottomUpRegion.contains(difference),
            Comment(
                rawValue:
                "difference=\(difference) "
                    + "silence=\(silence.artworkFrame) "
                    + "high=\(highBass.artworkFrame) "
                    + "topDown=\(topDownRegion) "
                    + "bottomUp=\(bottomUpRegion)"
            )
        )
    }

    private func visualQAState(
        document: LyricDocument
    ) -> RhythmPulseVisualQAState {
        RhythmPulseVisualQAState(
            palette: RhythmAccentPalette(
                colors: [
                    RhythmPulseColor(red: 0.93, green: 0.18, blue: 0.52),
                    RhythmPulseColor(red: 0.51, green: 0.25, blue: 0.98),
                    RhythmPulseColor(red: 0.03, green: 0.74, blue: 0.91),
                ]
            ),
            seed: 0xBA55,
            lanes: [.left, .right],
            isCadenceModeActive: true,
            cadenceModeLyricDocument: document,
            cadenceModePresentationTime: 89,
            cadenceModeBassLevel: nil
        )
    }

    private func bassVisualDocument(trackID: UUID) -> LyricDocument {
        LyricDocument(
            trackID: trackID,
            lines: [LyricLine(text: "Bass visual acceptance")]
        )
    }
}

private extension CadenceModeLyricsVisualTests {
    static func synchronizedDocument(trackID: UUID) -> LyricDocument {
        LyricDocument(
            trackID: trackID,
            lines: [
                LyricLine(
                    id: lyricLineID(1),
                    text: "We kept the signal low",
                    startTime: 62
                ),
                LyricLine(
                    id: lyricLineID(2),
                    text: "While the city disappeared",
                    startTime: 70
                ),
                LyricLine(
                    id: lyricLineID(3),
                    text: "Static blooming in the dark",
                    startTime: 78
                ),
                LyricLine(
                    id: lyricLineID(4),
                    text: "Every frequency was clear",
                    startTime: 86
                ),
                LyricLine(
                    id: lyricLineID(5),
                    text: "Until the morning found us",
                    startTime: 94
                ),
                LyricLine(
                    id: lyricLineID(6),
                    text: "Past the edge of every frame",
                    startTime: 102
                ),
                LyricLine(
                    id: lyricLineID(7),
                    text: "We were listening for silence",
                    startTime: 110
                ),
            ]
        )
    }

    static func lyricLineID(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, value
        ))
    }
}

private struct CadenceModeRecordsOnlyCapture {
    let contentSize: NSSize
    let pixelWidth: Int
    let pixelHeight: Int
    let expectedPixelWidth: Int
    let expectedPixelHeight: Int
    let pngData: Data
    let rgbaPixels: [UInt8]
    let artworkFrame: CGRect
    let artworkScale: CGFloat

    var byteCount: Int {
        pngData.count
    }

    func hasSamePNG(as other: Self) -> Bool {
        pngData == other.pngData
    }

    func hasSamePixels(as other: Self) -> Bool {
        rgbaPixels == other.rgbaPixels
    }

    func pixelDifferenceBounds(
        comparedTo other: Self
    ) -> CGRect? {
        guard pixelWidth == other.pixelWidth,
              pixelHeight == other.pixelHeight,
              rgbaPixels.count == other.rgbaPixels.count else {
            return nil
        }

        var minimumX = pixelWidth
        var minimumY = pixelHeight
        var maximumX = -1
        var maximumY = -1
        for pixelIndex in 0 ..< pixelWidth * pixelHeight {
            let offset = pixelIndex * 4
            guard rgbaPixels[offset ..< offset + 4]
                != other.rgbaPixels[offset ..< offset + 4] else {
                continue
            }
            let x = pixelIndex % pixelWidth
            let y = pixelIndex / pixelWidth
            minimumX = min(minimumX, x)
            minimumY = min(minimumY, y)
            maximumX = max(maximumX, x)
            maximumY = max(maximumY, y)
        }
        guard maximumX >= minimumX, maximumY >= minimumY else {
            return nil
        }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX + 1,
            height: maximumY - minimumY + 1
        )
    }

    func pixelRect(
        for pointRect: CGRect,
        verticallyFlipped: Bool
    ) -> CGRect {
        let scaleX = CGFloat(pixelWidth) / contentSize.width
        let scaleY = CGFloat(pixelHeight) / contentSize.height
        let originY = verticallyFlipped
            ? contentSize.height - pointRect.maxY
            : pointRect.minY
        return CGRect(
            x: pointRect.minX * scaleX,
            y: originY * scaleY,
            width: pointRect.width * scaleX,
            height: pointRect.height * scaleY
        )
        .intersection(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    }
}

@MainActor
private enum CadenceModeRecordsOnlyRenderer {
    static func capture(
        fixture: DocumentationScreenshotFixture,
        visualQAState: RhythmPulseVisualQAState,
        reduceMotion: Bool,
        filename: String,
        expectedArtworkScale: ClosedRange<CGFloat> = 1 ... 1
    ) async throws -> CadenceModeRecordsOnlyCapture {
        let contentSize = NSSize.minimum
        let trackID = try #require(fixture.model.currentPlaybackTrack?.id)
        let visualReadiness = CadenceModeVisualReadinessTracker()
        fixture.readinessTracker.prepareForCapture(.nowPlaying)
        let rootView = CadenceRootView(model: fixture.model)
            .frame(width: contentSize.width, height: contentSize.height)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .environment(\.colorScheme, .dark)
            .environment(
                \.cadenceModeVisualQABackgroundReduceMotionOverride,
                true
            )
            .environment(
                \.cadenceModeVisualQAReduceMotionOverride,
                reduceMotion
            )
            .environment(
                \.cadenceModeVisualReadinessObserver,
                visualReadiness.observer
            )
            .environment(\.rhythmPulseVisualQAState, visualQAState)
            .environment(
                \.nowPlayingReadinessObserver,
                NowPlayingReadinessObserver(
                    notify: fixture.readinessTracker.didRenderNowPlaying
                )
            )
            .environment(\.visualRegressionUsesStableSystemControls, true)
            .environment(\.visualRegressionFreezesHighlights, true)
            .environment(\.controlActiveState, .key)
            .defaultAppStorage(DocumentationScreenshotDefaults.userDefaults)
            .environment(\.visualRegressionHidesPreviewChrome, true)
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
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        window.setContentSize(contentSize)
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }

        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        try await fixture.waitUntilReady(for: .nowPlaying)
        let artworkSnapshot = try await visualReadiness.waitUntilReady(
            trackID: trackID,
            expectedArtworkScale: expectedArtworkScale
        )
        await Task.yield()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            throw CadenceModeScreenshotError.captureUnavailable
        }
        hostingView.cacheDisplay(
            in: hostingView.bounds,
            to: representation
        )
        guard let data = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw CadenceModeScreenshotError.encodingFailed
        }
        let rgbaPixels = try rgbaPixels(from: representation)
        Attachment.record([UInt8](data), named: filename)

        let scale = window.backingScaleFactor
        return CadenceModeRecordsOnlyCapture(
            contentSize: hostingView.bounds.size,
            pixelWidth: representation.pixelsWide,
            pixelHeight: representation.pixelsHigh,
            expectedPixelWidth: Int((contentSize.width * scale).rounded()),
            expectedPixelHeight: Int((contentSize.height * scale).rounded()),
            pngData: data,
            rgbaPixels: rgbaPixels,
            artworkFrame: artworkSnapshot.artworkFrame,
            artworkScale: artworkSnapshot.artworkScale
        )
    }

    private static func rgbaPixels(
        from representation: NSBitmapImageRep
    ) throws -> [UInt8] {
        guard let image = representation.cgImage else {
            throw CadenceModeScreenshotError.pixelConversionFailed
        }
        let width = representation.pixelsWide
        let height = representation.pixelsHigh
        let bytesPerRow = width * 4
        var pixels = [UInt8](
            repeating: 0,
            count: bytesPerRow * height
        )
        let didDraw = pixels.withUnsafeMutableBytes { bytes in
            let alphaInfo = CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: alphaInfo.rawValue
            ) else {
                return false
            }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard didDraw else {
            throw CadenceModeScreenshotError.pixelConversionFailed
        }
        return pixels
    }
}
