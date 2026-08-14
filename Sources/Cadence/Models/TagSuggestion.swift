import Foundation

enum TagSuggestionEvidence: Int, Hashable, Sendable {
    case album
    case artist
    case cooccurrence
}

struct TagSuggestionCandidate: Hashable, Sendable {
    let tag: TagPreview
    let target: TagAssignmentTarget
    let evidence: TagSuggestionEvidence
    let supportCount: Int
    let reason: String
}

struct TagSuggestion: Identifiable, Hashable, Sendable {
    let tag: TagPreview
    let evidence: TagSuggestionEvidence
    let supportCount: Int
    let reason: String
    let eligibleTargets: [TagAssignmentTarget]
    let selectionCount: Int

    var id: TagPreview.ID {
        tag.id
    }
}
