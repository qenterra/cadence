import Foundation

extension CadenceAppModel {
    var tagSuggestions: [TagSuggestion] {
        tagSuggestions(for: tagEditingSelection.targets)
    }

    func tagSuggestions(
        for targets: [TagAssignmentTarget]
    ) -> [TagSuggestion] {
        TagSuggestionEngine(
            tracks: tracks,
            tags: tags,
            assignments: tagAssignments,
            exclusions: tagExclusions,
            dismissals: dismissedTagSuggestions
        )
        .suggestions(for: targets)
    }
}
