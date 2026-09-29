@testable import Cadence
import Testing

@MainActor
struct NowPlayingTagControlTests {
    @Test("The tag entry rests as a plus and expands into a focused field")
    func tagEntryPresentation() {
        var state = NowPlayingTagEntryState()

        #expect(state.presentation.showsAddButton)
        #expect(!state.presentation.showsTextField)
        #expect(!state.presentation.requestsFocus)

        state.beginEditing()

        #expect(!state.presentation.showsAddButton)
        #expect(state.presentation.showsTextField)
        #expect(state.presentation.requestsFocus)
    }

    @Test("Return trims a tag while Escape restores the compact state")
    func tagEntrySubmissionAndCancellation() {
        var state = NowPlayingTagEntryState()
        state.beginEditing()

        #expect(state.submission(from: "  Mood / Calm  ") == "Mood / Calm")
        #expect(state.submission(from: "  \n  ") == nil)

        state.cancelEditing()

        #expect(state.presentation.showsAddButton)
        #expect(!state.presentation.showsTextField)
        #expect(!state.presentation.requestsFocus)
    }

    @Test("A removable pill keeps its remove control visible without hover")
    func removablePillKeepsRemoveControlVisible() {
        let resting = CadenceTagPillPresentation.resolve(
            isHovered: false,
            isFocused: false,
            hasRemoveAction: true
        )
        let hovered = CadenceTagPillPresentation.resolve(
            isHovered: true,
            isFocused: false,
            hasRemoveAction: true
        )
        let focused = CadenceTagPillPresentation.resolve(
            isHovered: false,
            isFocused: true,
            hasRemoveAction: true
        )

        #expect(resting.showsRemoveButton)
        #expect(hovered.showsRemoveButton)
        #expect(focused.showsRemoveButton)
        #expect(resting.reservedTrailingWidth == hovered.reservedTrailingWidth)
        #expect(hovered.reservedTrailingWidth == focused.reservedTrailingWidth)
        #expect(resting.reservedTrailingWidth > 0)
    }

    @Test("A non-removable pill never allocates or exposes a remove control")
    func nonRemovablePill() {
        let presentation = CadenceTagPillPresentation.resolve(
            isHovered: true,
            isFocused: true,
            hasRemoveAction: false
        )

        #expect(!presentation.showsRemoveButton)
        #expect(presentation.reservedTrailingWidth == 0)
    }
}
