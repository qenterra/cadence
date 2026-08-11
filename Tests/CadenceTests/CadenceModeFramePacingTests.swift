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

        let fixture = try await DocumentationScreenshotFixture.make()
        fixture.model.presentNowPlaying()
        fixture.model.selectedNowPlayingPanel = .lyrics

        let contentSize = NSSize(width: 1512, height: 982)
        let hostingView = NSHostingView(
            rootView: CadenceRootView(model: fixture.model)
                .frame(width: contentSize.width, height: contentSize.height)
                .environment(\.colorScheme, ColorScheme.dark)
                .tint(CadenceTheme.primaryAccent)
        )
        let window = makeWindow(
            contentSize: contentSize,
            contentView: hostingView
        )
        defer {
            window.orderOut(nil)
            window.close()
        }

        try await Task.sleep(for: .milliseconds(500))
        window.makeFirstResponder(hostingView)

        let expectedFramesPerSecond = window.screen?
            .maximumFramesPerSecond ?? 60
        let probe = CadenceDisplayLinkProbe()
        let displayLink = makeDisplayLink(
            window: window,
            probe: probe,
            expectedFramesPerSecond: expectedFramesPerSecond
        )
        displayLink.add(to: .main, forMode: .common)
        try await Task.sleep(for: .seconds(2))
        let baselineReport = try #require(
            probe.report(
                expectedFramesPerSecond: expectedFramesPerSecond
            )
        )
        probe.reset()

        sendKey(type: .keyDown, keyCode: 6, characters: "z", to: window)
        try await Task.sleep(for: .milliseconds(80))
        sendKey(type: .keyDown, keyCode: 7, characters: "x", to: window)
        try await Task.sleep(for: .milliseconds(260))
        sendKey(type: .keyUp, keyCode: 6, characters: "z", to: window)
        sendKey(type: .keyUp, keyCode: 7, characters: "x", to: window)
        try await Task.sleep(for: .milliseconds(440))
        probe.reset()

        try await Task.sleep(for: .seconds(2))
        let idleCadenceReport = try #require(
            probe.report(
                expectedFramesPerSecond: expectedFramesPerSecond
            )
        )
        probe.reset()

        let tapLatencySummary = try await stressWithDiscreteTaps(
            window: window,
            duration: 4
        )
        displayLink.invalidate()

        let report = try #require(
            probe.report(
                expectedFramesPerSecond: expectedFramesPerSecond
            )
        )
        let cadenceSummary = report.summary + "; " + tapLatencySummary
        print(baselineReport.summary)
        print("Idle " + idleCadenceReport.summary)
        print(cadenceSummary)

        #expect(
            baselineReport.deliveredFrameRatio
                >= Self.minimumDeliveredFrameRatio,
            Comment(rawValue: baselineReport.summary)
        )
        #expect(
            idleCadenceReport.deliveredFrameRatio
                >= Self.minimumDeliveredFrameRatio,
            Comment(rawValue: "Idle " + idleCadenceReport.summary)
        )
        #expect(
            report.deliveredFrameRatio
                >= Self.minimumDeliveredFrameRatio,
            Comment(rawValue: cadenceSummary)
        )
        #expect(
            report.deliveredFramesPerSecond
                >= baselineReport.deliveredFramesPerSecond
                * Self.minimumDeliveredFrameRatio,
            Comment(
                rawValue: baselineReport.summary + "; " + cadenceSummary
            )
        )
        #expect(
            report.longestFrameDuration
                <= report.frameBudget * Self.maximumFrameIntervalMultiplier
                + Self.clockPrecisionTolerance,
            Comment(rawValue: cadenceSummary)
        )
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
    private static let minimumDeliveredFrameRatio = 0.995
    private static let maximumFrameIntervalMultiplier = 1.5

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
    ) async throws -> String {
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
        return String(
            format: "tap latency max %.2f ms, average %.2f ms",
            (tapDurations.max() ?? 0) * 1000,
            (tapDurations.reduce(0, +) / Double(tapDurations.count)) * 1000
        )
    }
}

@MainActor
private final class CadenceDisplayLinkProbe: NSObject {
    private var timestamps: [TimeInterval] = []

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

    var deliveredFrameRatio: Double {
        deliveredFramesPerSecond / expectedFramesPerSecond
    }

    var frameBudget: TimeInterval {
        1 / expectedFramesPerSecond
    }

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
