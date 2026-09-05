import AppKit
@testable import Cadence
import Testing

@MainActor
struct AppCommandRouterTests {
    @Test("Plain Space is captured at window scope unless a local surface owns it")
    func windowScopedSpaceDecision() {
        #expect(
            AppPlaybackKeyDecision.shouldHandle(
                eventType: .keyDown,
                keyCode: 49,
                isRepeat: false,
                modifiers: [],
                focus: .none
            )
        )
        #expect(
            AppPlaybackKeyDecision.shouldHandle(
                eventType: .keyDown,
                keyCode: 49,
                isRepeat: false,
                modifiers: [],
                focus: .trackTable
            )
        )
        #expect(
            !AppPlaybackKeyDecision.shouldHandle(
                eventType: .keyDown,
                keyCode: 49,
                isRepeat: false,
                modifiers: [],
                focus: .textEditing
            )
        )
        #expect(
            !AppPlaybackKeyDecision.shouldHandle(
                eventType: .keyDown,
                keyCode: 49,
                isRepeat: false,
                modifiers: [],
                focus: .none,
                isLocallyOwned: true
            )
        )
    }

    @Test("Modified, repeated, and non-Space events stay in the responder chain")
    func unrelatedKeyEventsArePreserved() {
        #expect(
            !AppPlaybackKeyDecision.shouldHandle(
                eventType: .keyUp,
                keyCode: 49,
                isRepeat: false,
                modifiers: [],
                focus: .none
            )
        )
        #expect(
            !AppPlaybackKeyDecision.shouldHandle(
                eventType: .keyDown,
                keyCode: 49,
                isRepeat: true,
                modifiers: [],
                focus: .none
            )
        )
        #expect(
            !AppPlaybackKeyDecision.shouldHandle(
                eventType: .keyDown,
                keyCode: 49,
                isRepeat: false,
                modifiers: .command,
                focus: .none
            )
        )
        #expect(
            !AppPlaybackKeyDecision.shouldHandle(
                eventType: .keyDown,
                keyCode: 36,
                isRepeat: false,
                modifiers: [],
                focus: .none
            )
        )
    }

    @Test("Text editing keeps Space local")
    func textEditingBlocksPlayback() {
        var toggleCount = 0
        let router = AppCommandRouter(
            actions: AppCommandActions(
                hasCurrentItem: { true },
                hasPlaybackFailure: { false },
                togglePlayback: { toggleCount += 1 },
                previousTrack: {},
                nextTrack: {},
                adjustVolume: { _ in }
            )
        )

        #expect(
            !router.handle(
                .togglePlayback,
                focus: .textEditing
            )
        )
        #expect(toggleCount == 0)
    }

    @Test("Global playback commands mutate the playback boundary")
    func globalPlaybackCommands() {
        var isPlaying = false
        var movement = 0
        var volumeDelta: Double = 0
        let router = AppCommandRouter(
            actions: AppCommandActions(
                hasCurrentItem: { true },
                hasPlaybackFailure: { false },
                togglePlayback: { isPlaying.toggle() },
                previousTrack: { movement -= 1 },
                nextTrack: { movement += 1 },
                adjustVolume: { volumeDelta += $0 }
            )
        )

        #expect(router.handle(.togglePlayback, focus: .none))
        #expect(isPlaying)
        #expect(router.handle(.nextTrack, focus: .none))
        #expect(router.handle(.previousTrack, focus: .none))
        #expect(movement == 0)
        #expect(router.handle(.volumeUp, focus: .none))
        #expect(router.handle(.volumeDown, focus: .none))
        #expect(volumeDelta == 0)
    }

    @Test("Volume commands use the configured adjustment step")
    func configurableVolumeStep() {
        var deltas: [Double] = []
        let router = AppCommandRouter(
            actions: AppCommandActions(
                hasCurrentItem: { false },
                hasPlaybackFailure: { false },
                togglePlayback: {},
                previousTrack: {},
                nextTrack: {},
                adjustVolume: { deltas.append($0) },
                volumeStep: { VolumeAdjustmentStep.percent10.delta }
            )
        )

        #expect(router.handle(.volumeUp, focus: .none))
        #expect(router.handle(.volumeDown, focus: .none))
        #expect(deltas == [0.1, -0.1])
    }

    @Test("Playback failure requires its explicit Retry action")
    func failureBlocksToggle() {
        var toggleCount = 0
        let router = AppCommandRouter(
            actions: AppCommandActions(
                hasCurrentItem: { true },
                hasPlaybackFailure: { true },
                togglePlayback: { toggleCount += 1 },
                previousTrack: {},
                nextTrack: {},
                adjustVolume: { _ in }
            )
        )

        #expect(!router.handle(.togglePlayback, focus: .none))
        #expect(toggleCount == 0)
    }

    @Test("Shortcut reference uses native macOS key glyphs")
    func shortcutReferenceGlyphs() throws {
        let nextTrack = try #require(
            ShortcutCatalog.entries.first { $0.id == "next" }
        )

        #expect(nextTrack.keys == [.command, .rightArrow])
    }
}
