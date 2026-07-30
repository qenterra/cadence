import Foundation

struct SmartCollectionEvaluationContext: Hashable, Sendable {
    let effectiveTagsByTrackID: [TrackPreview.ID: [TagPreview]]
    let tagsByID: [TagPreview.ID: TagPreview]
    let favoriteTrackIDs: Set<TrackPreview.ID>
}

struct SmartCollectionRuleEvaluator: Sendable {
    func evaluate(
        root: SmartCollectionRuleGroup,
        tracks: [TrackPreview],
        context: SmartCollectionEvaluationContext
    ) -> [TrackPreview] {
        guard !root.children.isEmpty else {
            return tracks
        }
        return tracks.filter {
            matches(group: root, track: $0, context: context)
        }
    }

    private func matches(
        group: SmartCollectionRuleGroup,
        track: TrackPreview,
        context: SmartCollectionEvaluationContext
    ) -> Bool {
        switch group.combinator {
        case .all:
            group.children.allSatisfy {
                matches(node: $0, track: track, context: context)
            }
        case .any:
            group.children.contains {
                matches(node: $0, track: track, context: context)
            }
        }
    }

    private func matches(
        node: SmartCollectionRuleNode,
        track: TrackPreview,
        context: SmartCollectionEvaluationContext
    ) -> Bool {
        switch node {
        case let .condition(condition):
            let result = matches(
                condition: condition,
                track: track,
                context: context
            )
            return condition.isNegated ? !result : result
        case let .group(group):
            return matches(group: group, track: track, context: context)
        }
    }

    private func matches(
        condition: SmartCollectionRuleCondition,
        track: TrackPreview,
        context: SmartCollectionEvaluationContext
    ) -> Bool {
        switch condition.field {
        case .tag:
            tagMatches(condition, track: track, context: context)
        case .artist:
            textMatches(condition, candidate: track.artist)
        case .album:
            textMatches(condition, candidate: track.album)
        case .format:
            textMatches(condition, candidate: track.format)
        case .year:
            numberMatches(condition, candidate: track.year)
        case .rating:
            numberMatches(condition, candidate: track.rating)
        case .favorite:
            favoriteMatches(condition, track: track, context: context)
        }
    }

    private func tagMatches(
        _ condition: SmartCollectionRuleCondition,
        track: TrackPreview,
        context: SmartCollectionEvaluationContext
    ) -> Bool {
        guard
            condition.operator == .is,
            case let .tag(tagID?, scope) = condition.value
        else {
            return false
        }

        let effectiveTags = context.effectiveTagsByTrackID[track.id] ?? []
        switch scope {
        case .exact:
            return effectiveTags.contains { $0.id == tagID }
        case .includeSubtags:
            guard let selectedTag = context.tagsByID[tagID] else {
                return false
            }
            return effectiveTags.contains {
                $0.components.starts(with: selectedTag.components)
            }
        }
    }

    private func textMatches(
        _ condition: SmartCollectionRuleCondition,
        candidate: String
    ) -> Bool {
        guard case let .text(value) = condition.value else {
            return false
        }
        let trimmedValue = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedValue.isEmpty else {
            return false
        }
        let options: String.CompareOptions = [
            .caseInsensitive,
            .diacriticInsensitive,
        ]

        switch condition.operator {
        case .is:
            return candidate.compare(
                trimmedValue,
                options: options,
                locale: .current
            ) == .orderedSame
        case .contains:
            return candidate.range(
                of: trimmedValue,
                options: options,
                locale: .current
            ) != nil
        default:
            return false
        }
    }

    private func numberMatches(
        _ condition: SmartCollectionRuleCondition,
        candidate: Int
    ) -> Bool {
        switch (condition.operator, condition.value) {
        case let (.is, .integer(value?)):
            candidate == value
        case let (.greaterThan, .integer(value?)):
            candidate > value
        case let (.lessThan, .integer(value?)):
            candidate < value
        case let (.between, .integerRange(lower?, upper?)):
            (lower ... upper).contains(candidate)
        default:
            false
        }
    }

    private func favoriteMatches(
        _ condition: SmartCollectionRuleCondition,
        track: TrackPreview,
        context: SmartCollectionEvaluationContext
    ) -> Bool {
        guard
            condition.operator == .is,
            case let .boolean(expected) = condition.value
        else {
            return false
        }
        return context.favoriteTrackIDs.contains(track.id) == expected
    }
}
