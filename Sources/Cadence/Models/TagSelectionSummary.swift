import Foundation

enum TagSelectionState: Hashable, Sendable {
    case allDirect
    case mixedDirect
    case inherited
    case excluded
    case mixedSource
}

struct TagSelectionSummary: Identifiable, Hashable, Sendable {
    let tag: TagPreview
    let directCount: Int
    let inheritedCount: Int
    let excludedCount: Int
    let absentCount: Int
    let state: TagSelectionState

    var id: TagPreview.ID {
        tag.id
    }
}
