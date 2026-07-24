import Foundation

enum TagEditCommand: Hashable, Sendable {
    case assign(tagID: TagPreview.ID, targets: [TagAssignmentTarget])
    case removeDirect(tagID: TagPreview.ID, targets: [TagAssignmentTarget])
    case createAndAssign(path: String, targets: [TagAssignmentTarget])
    case excludeInherited(tagID: TagPreview.ID, trackIDs: [TrackPreview.ID])
    case restoreInheritance(tagID: TagPreview.ID, trackIDs: [TrackPreview.ID])
    case acceptSuggestion(tagID: TagPreview.ID, targets: [TagAssignmentTarget])
    case dismissSuggestion(tagID: TagPreview.ID, targets: [TagAssignmentTarget])

    var actionName: String {
        switch self {
        case let .assign(_, targets):
            "Assign Tag to \(targets.targetDescription)"
        case let .removeDirect(_, targets):
            "Remove Tag from \(targets.targetDescription)"
        case let .createAndAssign(_, targets):
            "Create and Assign Tag to \(targets.targetDescription)"
        case let .excludeInherited(_, trackIDs):
            "Exclude Inherited Tag from \(trackIDs.trackDescription)"
        case let .restoreInheritance(_, trackIDs):
            "Restore Tag Inheritance for \(trackIDs.trackDescription)"
        case let .acceptSuggestion(_, targets):
            "Accept Tag Suggestion for \(targets.targetDescription)"
        case let .dismissSuggestion(_, targets):
            "Dismiss Tag Suggestion for \(targets.targetDescription)"
        }
    }
}

struct TagSuggestionDismissal: Hashable, Sendable {
    let tagID: TagPreview.ID
    let target: TagAssignmentTarget
}

private extension [TagAssignmentTarget] {
    var targetDescription: String {
        let count = count
        let noun = switch first?.editingKind {
        case .albums:
            count == 1 ? "Album" : "Albums"
        case .tracks, nil:
            count == 1 ? "Track" : "Tracks"
        }
        return "\(count) \(noun)"
    }
}

private extension [TrackPreview.ID] {
    var trackDescription: String {
        "\(count) \(count == 1 ? "Track" : "Tracks")"
    }
}
