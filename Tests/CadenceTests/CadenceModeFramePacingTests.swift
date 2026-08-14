import AppKit
@testable import Cadence
import QuartzCore
import SwiftUI
import Testing

@MainActor
struct CadenceModeFramePacingTests {
    @Test("Cadence Mode keeps pace with the active display")
    func cadenceModeKeepsDisplayPacing() async throws {
        guard FileManager.default.fileExists(atPath: Self.runMarker.path) else {
            return
        }

        let surface = try await makeSurface()
        let window = surface.window
        defer {
            window.orderOut(nil)
            window.close()
        }

        try await Task.sleep(for: .milliseconds(500))
        window.makeFirstResponder(surface.hostingView)
        surface.displayLink.add(to: .main, forMode: .common)
        let baselineReport = try await measureFrames(surface)
        try await activateCadenceMode(surface)
        let idleCadenceReport = try await measureFrames(surface)
        try await beginMeasurement(surface.probe)
        let tapLatencyReport = try await stressWithDiscreteTaps(
            window: window,
            duration: 4
        )
        surface.displayLink.invalidate()
        let report = try #require(
            surface.probe.report(
                expectedFramesPerSecond: surface.expectedFramesPerSecond
            )
        )
        let cadenceSummary = report.summary + "; " + tapLatencyReport.summary
        print(baselineReport.summary)
        print("Idle " + idleCadenceReport.summary)
        print(cadenceSummary)

        expectBaselineFrameRate(
            baselineReport,
            expectedFramesPerSecond: surface.expectedFramesPerSecond
        )
        expectCadencePerformance(
            idleCadenceReport,
            expectedFramesPerSecond: surface.expectedFramesPerSecond,
            label: "Idle"
        )
        expectCadencePerformance(
            report,
            expectedFramesPerSecond: surface.expectedFramesPerSecond,
            label: "Active"
        )
        #expect(
            tapLatencyReport.maximum
                <= CadenceModePerformancePolicy.maximumInputLatency,
            Comment(rawValue: cadenceSummary)
        )
    }
}

private extension CadenceModeFramePacingTests {
    func makeSurface() async throws -> CadenceFramePacingSurface {
        let fixture = try await DocumentationScreenshotFixture.make()
        fixture.model.presentNowPlaying()
        fixture.model.selectedNowPlayingPanel = .lyrics
        let contentSize = NSSize(width: 1512, height: 982)
        let session = CadenceModeSession(automatesTiming: false)
        let hostingView = NSHostingView(
            rootView: CadenceRootView(
                model: fixture.model,
                cadenceModeSession: session
            )
            .frame(width: contentSize.width, height: contentSize.height)
            .environment(\.colorScheme, ColorScheme.dark)
            .tint(CadenceTheme.primaryAccent)
        )
        let window = makeWindow(contentSize: contentSize, contentView: hostingView)
        let expectedFramesPerSecond = window.screen?.maximumFramesPerSecond ?? 60
        let probe = CadenceDisplayLinkProbe()
        return CadenceFramePacingSurface(
            window: window,
            hostingView: hostingView,
            session: session,
            probe: probe,
            displayLink: makeDisplayLink(
                window: window,
                probe: probe,
                expectedFramesPerSecond: expectedFramesPerSecond
            ),
            expectedFramesPerSecond: expectedFramesPerSecond
        )
    }

    func measureFrames(
        _ surface: CadenceFramePacingSurface
    ) async throws -> CadenceFramePacingReport {
        try await beginMeasurement(surface.probe)
        try await Task.sleep(for: .seconds(2))
        return try #require(
            surface.probe.report(
                expectedFramesPerSecond: surface.expectedFramesPerSecond
            )
        )
    }

    func activateCadenceMode(
        _ surface: CadenceFramePacingSurface
    ) async throws {
        sendKey(type: .keyDown, keyCode: 6, characters: "z", to: surface.window)
        try await Task.sleep(for: .milliseconds(80))
        sendKey(type: .keyDown, keyCode: 7, characters: "x", to: surface.window)
        try await Task.sleep(for: .milliseconds(260))
        surface.session.pulseStore.reset()
        sendKey(type: .keyUp, keyCode: 6, characters: "z", to: surface.window)
        sendKey(type: .keyUp, keyCode: 7, characters: "x", to: surface.window)
        try await Task.sleep(for: .milliseconds(440))
    }

    private static var runMarker: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build/run-cadence-frame-pacing")
    }

    /// CADisplayLink timestamps may differ from their nominal cadence by a
    /// fraction of a microsecond due to floating-point clock conversion.
    private static let clockPrecisionTolerance: TimeInterval = 0.000_001

    private func expectCadencePerformance(
        _ report: CadenceFramePacingReport,
        expectedFramesPerSecond: Int,
        label: String
    ) {
        expectMinimumFrameRate(
            report,
            expectedFramesPerSecond: expectedFramesPerSecond,
            label: label
        )
        expectFrameBudget(report, label: label)
    }

    /// The pre-Cadence sample is a control for catastrophic system load, not
    /// a ProMotion acceptance target. Cadence Mode's idle and active samples
    /// below retain the full 110 FPS and 25 ms product gates.
    private func expectBaselineFrameRate(
        _ report: CadenceFramePacingReport,
        expectedFramesPerSecond: Int
    ) {
        #expect(
            report.deliveredFramesPerSecond
                >= Double(
                    min(
                        expectedFramesPerSecond,
                        CadenceModePerformancePolicy
                            .minimumSupportedFramesPerSecond
                    )
                ),
            Comment(rawValue: "Baseline " + report.summary)
        )
    }

    private func expectMinimumFrameRate(
        _ report: CadenceFramePacingReport,
        expectedFramesPerSecond: Int,
        label: String = "Baseline"
    ) {
        #expect(
            report.deliveredFramesPerSecond
                >= minimumDeliveredFramesPerSecond(
                    expectedFramesPerSecond: expectedFramesPerSecond
                ),
            Comment(rawValue: label + " " + report.summary)
        )
    }

    private func expectFrameBudget(
        _ report: CadenceFramePacingReport,
        label: String
    ) {
        #expect(
            report.longestFrameDuration
                <= CadenceModePerformancePolicy.maximumFrameDuration
                + Self.clockPrecisionTolerance,
            Comment(rawValue: label + " " + report.summary)
        )
    }

    private func minimumDeliveredFramesPerSecond(
        expectedFramesPerSecond: Int
    ) -> Double {
        CadenceModePerformancePolicy.minimumDeliveredFramesPerSecond(
            displayMaximumFramesPerSecond: expectedFramesPerSecond
        )
    }

    private func beginMeasurement(
        _ probe: CadenceDisplayLinkProbe
    ) async throws {
        probe.reset()
        try await Task.sleep(for: .milliseconds(400))
        probe.reset()
    }

    private func makeWindow(
        contentSize: NSSize,
        contentView: NSView
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Cadence Frame Pacing"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func makeDisplayLink(
        window: NSWindow,
        probe: CadenceDisplayLinkProbe,
        expectedFramesPerSecond: Int
    ) -> CADisplayLink {
        let displayLink = window.displayLink(
            target: probe,
            selector: #selector(CadenceDisplayLinkProbe.tick(_:))
        )
        let requestedRate = Float(expectedFramesPerSecond)
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: requestedRate,
            maximum: requestedRate,
            preferred: requestedRate
        )
        return displayLink
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

    private func stressWithDiscreteTaps(
        window: NSWindow,
        duration: TimeInterval
    ) async throws -> CadenceTapLatencyReport {
        let deadline = ProcessInfo.processInfo.systemUptime + duration
        var usesLeftLane = true
        var tapDurations: [TimeInterval] = []
        while ProcessInfo.processInfo.systemUptime < deadline {
            let keyCode: UInt16 = usesLeftLane ? 6 : 7
            let characters = usesLeftLane ? "z" : "x"
            let tapStartedAt = ProcessInfo.processInfo.systemUptime
            sendKey(
                type: .keyDown,
                keyCode: keyCode,
                characters: characters,
                to: window
            )
            sendKey(
                type: .keyUp,
                keyCode: keyCode,
                characters: characters,
                to: window
            )
            tapDurations.append(
                ProcessInfo.processInfo.systemUptime - tapStartedAt
            )
            usesLeftLane.toggle()
            try await Task.sleep(for: .milliseconds(180))
        }
        return CadenceTapLatencyReport(
            maximum: tapDurations.max() ?? 0,
            average: tapDurations.reduce(0, +) / Double(tapDurations.count)
        )
    }
}

@MainActor private struct CadenceFramePacingSurface {
    let window: NSWindow
    let hostingView: NSView
    let session: CadenceModeSession
    let probe: CadenceDisplayLinkProbe
    let displayLink: CADisplayLink
    let expectedFramesPerSecond: Int
}

private struct CadenceTapLatencyReport {
    let maximum: TimeInterval
    let average: TimeInterval

    var summary: String {
        String(
            format: "tap latency max %.2f ms, average %.2f ms",
            maximum * 1000,
            average * 1000
        )
    }
}

@MainActor
private final class CadenceDisplayLinkProbe: NSObject {
    private var timestamps: [TimeInterval] = []

    override init() {
        timestamps.reserveCapacity(2000)
        super.init()
    }

    @objc func tick(_ displayLink: CADisplayLink) {
        timestamps.append(displayLink.timestamp)
    }

    func reset() {
        timestamps.removeAll(keepingCapacity: true)
    }

    func report(
        expectedFramesPerSecond: Int
    ) -> CadenceFramePacingReport? {
        guard
            timestamps.count > 2,
            let firstTimestamp = timestamps.first,
            let lastTimestamp = timestamps.last,
            lastTimestamp > firstTimestamp
        else {
            return nil
        }

        let intervals = zip(timestamps, timestamps.dropFirst()).map {
            (duration: $1 - $0, offset: $0 - firstTimestamp)
        }
        let elapsed = lastTimestamp - firstTimestamp
        let deliveredFramesPerSecond = Double(intervals.count) / elapsed
        let expectedFramesPerSecond = Double(expectedFramesPerSecond)
        let longestInterval = intervals.max {
            $0.duration < $1.duration
        }
        return CadenceFramePacingReport(
            expectedFramesPerSecond: expectedFramesPerSecond,
            deliveredFramesPerSecond: deliveredFramesPerSecond,
            longestFrameDuration: longestInterval?.duration ?? .infinity,
            longestFrameOffset: longestInterval?.offset ?? .infinity
        )
    }
}

private struct CadenceFramePacingReport {
    let expectedFramesPerSecond: Double
    let deliveredFramesPerSecond: Double
    let longestFrameDuration: TimeInterval
    let longestFrameOffset: TimeInterval

    var summary: String {
        String(
            format: "Cadence frame pacing: %.2f/%.0f FPS, longest %.2f ms at %.2f s",
            deliveredFramesPerSecond,
            expectedFramesPerSecond,
            longestFrameDuration * 1000,
            longestFrameOffset
        )
    }
}
