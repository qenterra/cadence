import Foundation

struct ProductionSmartCollectionIndex: Sendable {
    let tracks: [LibraryTrackProjection]
    let effectiveTagIDsByTrackID: [UUID: Set<UUID>]
    let tagsByID: [UUID: LibraryTagProjection]
}

struct ProductionSmartCollectionCandidate: Sendable {
    let id: UUID
    let artist: String
    let album: String
    let year: Int?
    let codec: String
    let isFavorite: Bool
    let effectiveTagIDs: Set<UUID>
}

struct ProductionSmartCollectionEvaluation: Sendable {
    let orderedTrackIDs: [UUID]
    let totalDuration: TimeInterval

    var count: Int {
        orderedTrackIDs.count
    }
}

struct ProductionSmartCollectionResultPage: Sendable {
    let items: [LibraryTrackProjection]
    let nextOffset: Int?
}

struct ProductionSmartCollectionRuleData: Sendable {
    let options: SmartCollectionRuleOptions
    let tags: [LibraryTagProjection]

    static let empty = ProductionSmartCollectionRuleData(
        options: .empty,
        tags: []
    )
}

struct ProductionSmartCollectionEvaluator: Sendable {
    func evaluate(
        root: SmartCollectionRuleGroup,
        index: ProductionSmartCollectionIndex
    ) -> [LibraryTrackProjection] {
        let candidates = index.tracks.map { track in
            ProductionSmartCollectionCandidate(
                id: track.id,
                artist: track.artist,
                album: track.album,
                year: track.year,
                codec: track.codec,
                isFavorite: track.isFavorite,
                effectiveTagIDs: index.effectiveTagIDsByTrackID[track.id] ?? []
            )
        }
        let matchingIDs = Set(
            evaluateIDs(
                root: root,
                candidates: candidates,
                tagsByID: index.tagsByID
            )
        )
        return index.tracks.filter { matchingIDs.contains($0.id) }
    }

    func evaluateIDs(
        root: SmartCollectionRuleGroup,
        candidates: [ProductionSmartCollectionCandidate],
        tagsByID: [UUID: LibraryTagProjection]
    ) -> [UUID] {
        guard !root.children.isEmpty else {
            return candidates.map(\.id)
        }
        return candidates.compactMap { candidate in
            matches(
                group: root,
                candidate: candidate,
                tagsByID: tagsByID
            ) ? candidate.id : nil
        }
    }

    private func matches(
        group: SmartCollectionRuleGroup,
        candidate: ProductionSmartCollectionCandidate,
        tagsByID: [UUID: LibraryTagProjection]
    ) -> Bool {
        switch group.combinator {
        case .all:
            group.children.allSatisfy {
                matches(
                    node: $0,
                    candidate: candidate,
                    tagsByID: tagsByID
                )
            }
        case .any:
            group.children.contains {
                matches(
                    node: $0,
                    candidate: candidate,
                    tagsByID: tagsByID
                )
            }
        }
    }

    private func matches(
        node: SmartCollectionRuleNode,
        candidate: ProductionSmartCollectionCandidate,
        tagsByID: [UUID: LibraryTagProjection]
    ) -> Bool {
        switch node {
        case let .condition(condition):
            guard condition.field != .rating else {
                return false
            }
            let result = matches(
                condition: condition,
                candidate: candidate,
                tagsByID: tagsByID
            )
            return condition.isNegated ? !result : result
        case let .group(group):
            return matches(
                group: group,
                candidate: candidate,
                tagsByID: tagsByID
            )
        }
    }

    private func matches(
        condition: SmartCollectionRuleCondition,
        candidate: ProductionSmartCollectionCandidate,
        tagsByID: [UUID: LibraryTagProjection]
    ) -> Bool {
        switch condition.field {
        case .tag:
            tagMatches(
                condition,
                candidate: candidate,
                tagsByID: tagsByID
            )
        case .artist:
            textMatches(condition, candidate: candidate.artist)
        case .album:
            textMatches(condition, candidate: candidate.album)
        case .format:
            textMatches(condition, candidate: candidate.codec)
        case .year:
            numberMatches(condition, candidate: candidate.year ?? 0)
        case .rating:
            false
        case .favorite:
            booleanMatches(condition, candidate: candidate.isFavorite)
        }
    }

    private func tagMatches(
        _ condition: SmartCollectionRuleCondition,
        candidate: ProductionSmartCollectionCandidate,
        tagsByID: [UUID: LibraryTagProjection]
    ) -> Bool {
        guard
            condition.operator == .is,
            case let .tag(rawTagID?, scope) = condition.value,
            let tagID = UUID(uuidString: rawTagID)
        else {
            return false
        }
        let effectiveIDs = candidate.effectiveTagIDs
        switch scope {
        case .exact:
            return effectiveIDs.contains(tagID)
        case .includeSubtags:
            guard let selected = tagsByID[tagID] else {
                return false
            }
            let selectedComponents = pathComponents(selected.displayPath)
            return effectiveIDs.contains { effectiveID in
                guard let tag = tagsByID[effectiveID] else {
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
