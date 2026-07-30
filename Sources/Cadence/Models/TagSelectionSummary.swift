import Foundation

enum TagSelectionState: Hashable, Sendable {
    case allDirect
    case mixedDirect
    case inherited
    case excluded
    case mixedSource

    var title: String {
        switch self {
        case .allDirect:
            "Assigned to all"
        case .mixedDirect:
            "Assigned to some"
        case .inherited:
            "Inherited"
        case .excluded:
            "Excluded"
        case .mixedSource:
            "Mixed sources"
        }
    }
}

struct TagSelectionSummary: Identifiable, Hashable, Sendable {
    let tag: TagPreview
    let selectionCount: Int
    let directCount: Int
    let inheritedCount: Int
    let excludedCount: Int
    let absentCount: Int
    let state: TagSelectionState

    var id: TagPreview.ID {
        tag.id
    }

    var excludeApplicableCount: Int {
        inheritedCount
    }

    var restoreApplicableCount: Int {
        excludedCount
    }

    var sourceDescription: String {
        switch state {
        case .allDirect:
            selectionCount == 1 ? "Direct assignment" : "Assigned to all \(selectionCount)"
        case .mixedDirect:
            "\(directCount) of \(selectionCount) assigned"
        case .inherited:
            selectionCount == 1 ? "Inherited from album" : "Inherited by all \(selectionCount)"
        case .excluded:
            selectionCount == 1 ? "Album tag excluded" : "Excluded by all \(selectionCount)"
        case .mixedSource:
            [
                directCount > 0 ? "\(directCount) direct" : nil,
                inheritedCount > 0 ? "\(inheritedCount) inherited" : nil,
                excludedCount > 0 ? "\(excludedCount) excluded" : nil,
                absentCount > 0 ? "\(absentCount) absent" : nil,
            ]
            .compactMap(\.self)
            .joined(separator: " · ")
        }
    }
}
