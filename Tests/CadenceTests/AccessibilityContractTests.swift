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
                usesStableSystemControls: false,
                reduceTransparency: false
            ) == .nativeGlass
        )
        #expect(
            CadenceGlassSurfacePresentation.resolve(
                usesStableSystemControls: false,
                reduceTransparency: true
            ) == .opaqueFallback
        )
        #expect(AdaptiveLayoutPolicy.animation(reduceMotion: true) == nil)
        #expect(
            BrowserRowVisualState(
                isSelected: true,
                isIncreasedContrast: true
            ).selectionAdornment == .strongFill
        )
        #expect(
            BrowserRowVisualState(
                isSelected: false,
                isFocused: true,
                isIncreasedContrast: true
            ).borderWidth == 2
        )
    }

    @Test("Shared selection state uses a fill and a focus outline")
    func sharedSelectionChrome() {
        let selected = BrowserRowVisualState(isSelected: true)
        let focused = BrowserRowVisualState(
            isSelected: false,
            isFocused: true
        )

        #expect(selected.selectionAdornment == .fill)
        #expect(selected.outlinePresentation == .none)
        #expect(focused.selectionAdornment == .none)
        #expect(focused.outlinePresentation == .focus)
    }

    @Test("Hidden favorite presentation blocks pointer interaction but stays accessible")
    func hiddenFavoriteControlPresentation() {
        let hidden = FavoriteControlPresentation.resolve(
            isHovered: false,
            isFocused: false
        )

        #expect(hidden.visualOpacity == 0)
        #expect(!hidden.acceptsPointerInteraction)
        #expect(hidden.isAccessibilityVisible)
    }

    @Test("Focused favorite presentation reveals the control")
    func focusedFavoriteControlPresentation() {
        let focused = FavoriteControlPresentation.resolve(
            isHovered: false,
            isFocused: true
        )

        #expect(focused.visualOpacity == 1)
        #expect(focused.acceptsPointerInteraction)
        #expect(focused.isAccessibilityVisible)
    }

    @Test("Hovered favorite presentation reveals the control")
    func hoveredFavoriteControlPresentation() {
        let hovered = FavoriteControlPresentation.resolve(
            isHovered: true,
            isFocused: false
        )

        #expect(hovered.visualOpacity == 1)
        #expect(hovered.acceptsPointerInteraction)
        #expect(hovered.isAccessibilityVisible)
    }

    @Test("Keyboard-focused track actions materialize their full menu")
    func keyboardFocusedTrackActionsMaterialize() {
        let policy = TrackRowActionMenuMaterializationPolicy.production

        #expect(
            policy.materializesFullActions(
                isHovered: false,
                isSelected: false,
                isFocused: false,
                isKeyboardFocused: true
            )
        )
    }

    @Test("Accessibility-focused track actions materialize their full menu")
    func accessibilityFocusedTrackActionsMaterialize() {
        let policy = TrackRowActionMenuMaterializationPolicy.production

        #expect(
            policy.materializesFullActions(
                isHovered: false,
                isSelected: false,
                isFocused: false,
                isAccessibilityFocused: true
            )
        )
    }

    @Test("Favorite symbol effect presentation is disabled with Reduce Motion")
    func favoriteSymbolEffectPresentation() {
        let reduced = CadenceSymbolEffectPresentation.resolve(
            trigger: 2,
            reduceMotion: true
        )

        #expect(!reduced.isEnabled)
        #expect(reduced.trigger == 2)
    }
}
