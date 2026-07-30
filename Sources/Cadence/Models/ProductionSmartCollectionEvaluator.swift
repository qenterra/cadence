import Foundation

struct ProductionSmartCollectionIndex: Sendable {
    let tracks: [LibraryTrackProjection]
    let effectiveTagIDsByTrackID: [UUID: Set<UUID>]
    let tagsByID: [UUID: LibraryTagProjection]

    static let empty = ProductionSmartCollectionIndex(
        tracks: [],
        effectiveTagIDsByTrackID: [:],
        tagsByID: [:]
    )
}

struct ProductionSmartCollectionEvaluator: Sendable {
    func evaluate(
        root: SmartCollectionRuleGroup,
        index: ProductionSmartCollectionIndex
    ) -> [LibraryTrackProjection] {
        guard !root.children.isEmpty else {
            return index.tracks
        }
        return index.tracks.filter {
            matches(group: root, track: $0, index: index)
        }
    }

    private func matches(
        group: SmartCollectionRuleGroup,
        track: LibraryTrackProjection,
        index: ProductionSmartCollectionIndex
    ) -> Bool {
        switch group.combinator {
        case .all:
            group.children.allSatisfy {
                matches(node: $0, track: track, index: index)
            }
        case .any:
            group.children.contains {
                matches(node: $0, track: track, index: index)
            }
        }
    }

    private func matches(
        node: SmartCollectionRuleNode,
        track: LibraryTrackProjection,
        index: ProductionSmartCollectionIndex
    ) -> Bool {
        switch node {
        case let .condition(condition):
            let result = matches(
                condition: condition,
                track: track,
                index: index
            )
            return condition.isNegated ? !result : result
        case let .group(group):
            return matches(group: group, track: track, index: index)
        }
    }

    private func matches(
        condition: SmartCollectionRuleCondition,
        track: LibraryTrackProjection,
        index: ProductionSmartCollectionIndex
    ) -> Bool {
        switch condition.field {
        case .tag:
            tagMatches(condition, track: track, index: index)
        case .artist:
            textMatches(condition, candidate: track.artist)
        case .album:
            textMatches(condition, candidate: track.album)
        case .format:
            textMatches(condition, candidate: track.codec)
        case .year:
            numberMatches(condition, candidate: track.year ?? 0)
        case .rating:
            numberMatches(condition, candidate: 0)
        case .favorite:
            booleanMatches(condition, candidate: track.isFavorite)
        }
    }

    private func tagMatches(
        _ condition: SmartCollectionRuleCondition,
        track: LibraryTrackProjection,
        index: ProductionSmartCollectionIndex
    ) -> Bool {
        guard
            condition.operator == .is,
            case let .tag(rawTagID?, scope) = condition.value,
            let tagID = UUID(uuidString: rawTagID)
        else {
            return false
        }
        let effectiveIDs = index.effectiveTagIDsByTrackID[track.id] ?? []
        switch scope {
        case .exact:
            return effectiveIDs.contains(tagID)
        case .includeSubtags:
            guard let selected = index.tagsByID[tagID] else {
                return false
            }
            let selectedComponents = pathComponents(selected.displayPath)
            return effectiveIDs.contains { effectiveID in
                guard let tag = index.tagsByID[effectiveID] else {
                    return false
                }
                return pathComponents(tag.displayPath)
                    .starts(with: selectedComponents)
            }
        }
    }

    private func textMatches(
        _ condition: SmartCollectionRuleCondition,
        candidate: String
    ) -> Bool {
        guard case let .text(rawValue) = condition.value else {
            return false
        }
        let candidate = SearchNormalizer.normalize(candidate)
        let value = SearchNormalizer.normalize(rawValue)
        guard !value.isEmpty else {
            return false
        }
        switch condition.operator {
        case .is:
            return candidate == value
        case .contains:
            return candidate.contains(value)
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
            min(lower, upper) ... max(lower, upper) ~= candidate
        default:
            false
        }
    }

    private func booleanMatches(
        _ condition: SmartCollectionRuleCondition,
        candidate: Bool
    ) -> Bool {
        guard
            condition.operator == .is,
            case let .boolean(value) = condition.value
        else {
            return false
        }
        return candidate == value
    }

    private func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/").map {
            SearchNormalizer.normalize(String($0))
        }
    }
}
