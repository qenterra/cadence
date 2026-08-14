import Foundation

extension CadenceAppModel {
    var tagSelectionSummaries: [TagSelectionSummary] {
        guard !tagEditingSelection.isEmpty else {
            return []
        }

        return tags.compactMap { tag in
            tagSelectionSummary(for: tag)
        }
        .sorted {
            $0.tag.displayPath.localizedStandardCompare($1.tag.displayPath) == .orderedAscending
        }
    }

    private func tagSelectionSummary(
        for tag: TagPreview
    ) -> TagSelectionSummary? {
        var directCount = 0
        var inheritedCount = 0
        var excludedCount = 0
        var absentCount = 0

        for target in tagEditingSelection.targets {
            switch tagSource(tagID: tag.id, target: target) {
            case .direct:
                directCount += 1
            case .inherited:
                inheritedCount += 1
            case .excluded:
                excludedCount += 1
            case .absent:
                absentCount += 1
            }
        }

        guard directCount + inheritedCount + excludedCount > 0 else {
            return nil
        }

        return TagSelectionSummary(
            tag: tag,
            directCount: directCount,
            inheritedCount: inheritedCount,
            excludedCount: excludedCount,
            absentCount: absentCount,
            state: tagSelectionState(
                directCount: directCount,
                inheritedCount: inheritedCount,
                excludedCount: excludedCount,
                totalCount: tagEditingSelection.count
            )
        )
    }

    private func tagSource(
        tagID: TagPreview.ID,
        target: TagAssignmentTarget
    ) -> TagSelectionSource {
        switch target {
        case .album:
            return tagAssignments.contains(
                TagAssignmentPreview(tagID: tagID, target: target)
            ) ? .direct : .absent
        case let .track(trackID):
            if tagAssignments.contains(
                TagAssignmentPreview(tagID: tagID, target: target)
            ) {
                return .direct
            }
            guard let track = tracks.first(where: { $0.id == trackID }) else {
                return .absent
            }
            let hasAlbumAssignment = tagAssignments.contains(
                TagAssignmentPreview(tagID: tagID, target: .album(track.albumID))
            )
            guard hasAlbumAssignment else {
                return .absent
            }
            return tagExclusions.contains(
                TagExclusionPreview(tagID: tagID, trackID: trackID)
            ) ? .excluded : .inherited
        }
    }

    private func tagSelectionState(
        directCount: Int,
        inheritedCount: Int,
        excludedCount: Int,
        totalCount: Int
    ) -> TagSelectionState {
        if directCount == totalCount {
            return .allDirect
        }
        if directCount > 0 {
            return inheritedCount > 0 || excludedCount > 0
                ? .mixedSource
                : .mixedDirect
        }
        if inheritedCount == totalCount {
            return .inherited
        }
        if excludedCount == totalCount {
            return .excluded
        }
        return .mixedSource
    }
}

private enum TagSelectionSource {
    case direct
    case inherited
    case excluded
    case absent
}
