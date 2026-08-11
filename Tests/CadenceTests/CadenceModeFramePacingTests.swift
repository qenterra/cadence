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

        sendKey(keyCode: 6, characters: "z", to: window)
        try await Task.sleep(for: .milliseconds(80))
        sendKey(keyCode: 7, characters: "x", to: window)
        try await Task.sleep(for: .milliseconds(700))
        probe.reset()

        let inputTask = Task { @MainActor in
            for index in 0 ..< 40 {
                guard !Task.isCancelled else {
                    return
                }
                let usesLeftLane = index.isMultiple(of: 2)
                sendKey(
                    keyCode: usesLeftLane ? 6 : 7,
                    characters: usesLeftLane ? "z" : "x",
                    to: window
                )
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        try await Task.sleep(for: .seconds(4))
        inputTask.cancel()
        displayLink.invalidate()

        let report = try #require(
            probe.report(
                expectedFramesPerSecond: expectedFramesPerSecond
            )
        )
        print(baselineReport.summary)
        print(report.summary)

        #expect(
            baselineReport.deliveredFrameRatio
                >= Self.minimumDeliveredFrameRatio,
            Comment(rawValue: baselineReport.summary)
        )
        #expect(
            report.deliveredFrameRatio
                >= Self.minimumDeliveredFrameRatio,
            Comment(rawValue: report.summary)
        )
        #expect(
            report.deliveredFramesPerSecond
                >= baselineReport.deliveredFramesPerSecond
                * Self.minimumDeliveredFrameRatio,
            Comment(
                rawValue: baselineReport.summary + "; " + report.summary
            )
        )
        #expect(
            report.longestFrameDuration
                <= report.frameBudget * Self.maximumFrameIntervalMultiplier
                + Self.clockPrecisionTolerance,
            Comment(rawValue: report.summary)
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

        let durations = zip(timestamps, timestamps.dropFirst()).map {
            $1 - $0
        }
        let elapsed = lastTimestamp - firstTimestamp
        let deliveredFramesPerSecond = Double(durations.count) / elapsed
        let expectedFramesPerSecond = Double(expectedFramesPerSecond)
        return CadenceFramePacingReport(
            expectedFramesPerSecond: expectedFramesPerSecond,
            deliveredFramesPerSecond: deliveredFramesPerSecond,
            longestFrameDuration: durations.max() ?? .infinity
        )
    }
}

private struct CadenceFramePacingReport {
    let expectedFramesPerSecond: Double
    let deliveredFramesPerSecond: Double
    let longestFrameDuration: TimeInterval

    var deliveredFrameRatio: Double {
        deliveredFramesPerSecond / expectedFramesPerSecond
    }

    var frameBudget: TimeInterval {
        1 / expectedFramesPerSecond
    }

    var summary: String {
        String(
            format: "Cadence frame pacing: %.2f/%.0f FPS, longest %.2f ms",
            deliveredFramesPerSecond,
            expectedFramesPerSecond,
            longestFrameDuration * 1000
        )
    }
}
