import Foundation

extension CadenceAppModel {
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
