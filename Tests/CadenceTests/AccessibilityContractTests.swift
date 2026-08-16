@testable import Cadence
import Testing

struct AccessibilityContractTests {
    @Test("Compact and expanded navigation keep one predictable focus order")
    func navigationFocusOrder() {
        let sections = NavigationRailConfiguration.visibleSections(
            orderRawValue: NavigationRailConfiguration.defaultOrderRawValue,
            hiddenRawValue: ""
        )
        let expanded = NavigationRailAccessibilityContract.items(
            sections: sections,
            isExpanded: true,
            selected: .home
        )
        let compact = NavigationRailAccessibilityContract.items(
            sections: sections,
            isExpanded: false,
            selected: .home
        )

        #expect(expanded.map(\.label) == [
            "Collapse Sidebar",
            "Home",
            "Favorites",
            "Browse",
            "Tracks",
            "Albums",
            "Artists",
            "Playlists",
            "Smart Collections",
            "Tags",
            "Import Music",
            "Trash",
        ])
        #expect(compact.first?.label == "Expand Sidebar")
        #expect(compact.dropFirst().map(\.label) == expanded.dropFirst().map(\.label))
        #expect(expanded[1].value == "Selected")
        #expect(expanded[2].value.isEmpty)
        #expect(expanded.dropFirst().allSatisfy { !$0.hint.isEmpty })
    }

    @Test("Player transport exposes labels and disables unavailable actions")
    func disabledPlayerTransport() {
        let empty = PlayerBarAccessibilityContract.transportControls(
            hasPlaybackItem: false,
            isPlaying: false,
            repeatMode: .off
        )
        let playing = PlayerBarAccessibilityContract.transportControls(
            hasPlaybackItem: true,
            isPlaying: true,
            repeatMode: .one
        )

        #expect(empty.map(\.label) == [
            "Shuffle",
            "Previous Track",
            "Play",
            "Next Track",
            "Repeat Off",
            "Playback progress",
            "Queue",
        ])
        #expect(empty.allSatisfy { !$0.isEnabled })
        #expect(playing.map(\.label) == [
            "Shuffle",
            "Previous Track",
            "Pause",
            "Next Track",
            "Repeat One",
            "Playback progress",
            "Queue",
        ])
        #expect(!playing.contains { !$0.isEnabled })
    }

    @Test("System accessibility display preferences strengthen or simplify presentation")
    func displayPreferences() {
        #expect(
            CadenceGlassSurfacePresentation.resolve(
                reduceTransparency: false
            ) == .material
        )
        #expect(
            CadenceGlassSurfacePresentation.resolve(
                reduceTransparency: true
            ) == .opaque
        )
        #expect(AdaptiveLayoutPolicy.animation(reduceMotion: true) == nil)
        #expect(
            BrowserRowVisualState(
                isSelected: true,
                isIncreasedContrast: true
            ).fillRole == .selectedStrong
        )
        #expect(
            BrowserRowVisualState(
                isSelected: false,
                isFocused: true,
                isIncreasedContrast: true
            ).borderWidth == 2
        )
    }
}
