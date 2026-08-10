@testable import Cadence
import Foundation
import Testing

struct SmartCollectionRuleEvaluatorTests {
    @Test("Empty root matches every track in canonical input order")
    func emptyRoot() {
        let tracks = [track(id: 3), track(id: 1), track(id: 2)]
        let result = evaluator().evaluate(
            root: group(.all, []),
            tracks: tracks,
            context: context()
        )

        #expect(result.map(\.id) == [3, 1, 2])
    }

    @Test("Nested All, Any, and NOT compose deterministically")
    func booleanComposition() {
        let tracks = [
            track(id: 1, artist: "North Assembly", year: 2026),
            track(id: 2, artist: "North Assembly", year: 2024),
            track(id: 3, artist: "Mara Vale", year: 2026),
        ]
        let artist = condition(
            field: .artist,
            operator: .is,
            value: .text("north assembly")
        )
        let oldYear = condition(
            field: .year,
            operator: .lessThan,
            value: .integer(2025)
        )
        let root = group(
            .all,
            [
                .condition(artist),
                .group(group(.any, [.condition(oldYear.negated())])),
            ]
        )

        let result = evaluator().evaluate(
            root: root,
            tracks: tracks,
            context: context()
        )

        #expect(result.map(\.id) == [1])
    }

    @Test("Text matching ignores case and diacritics")
    func textMatching() {
        let tracks = [
            track(id: 1, artist: "Beyoncé", album: "Lumière"),
            track(id: 2, artist: "Relay", album: "Structures"),
        ]
        let root = group(
            .all,
            [
                .condition(
                    condition(
                        field: .artist,
                        operator: .is,
                        value: .text("BEYONCE")
                    )
                ),
                .condition(
                    condition(
                        field: .album,
                        operator: .contains,
                        value: .text("MIERE")
                    )
                ),
            ]
        )

        #expect(
            evaluator().evaluate(
                root: root,
                tracks: tracks,
                context: context()
            ).map(\.id) == [1]
        )
    }

    @Test("Numeric and favorite operators use current context")
    func numericAndFavorite() {
        let tracks = [
            track(id: 1, year: 2024, rating: 4),
            track(id: 2, year: 2026, rating: 5),
            track(id: 3, year: 2027, rating: 3),
        ]
        let root = group(
            .all,
            [
                .condition(
                    condition(
                        field: .year,
                        operator: .between,
                        value: .integerRange(lower: 2025, upper: 2027)
                    )
                ),
                .condition(
                    condition(
                        field: .rating,
                        operator: .greaterThan,
                        value: .integer(4)
                    )
                ),
                .condition(
                    condition(
                        field: .favorite,
                        operator: .is,
                        value: .boolean(true)
                    )
                ),
            ]
        )

        #expect(
            evaluator().evaluate(
                root: root,
                tracks: tracks,
                context: context(favorites: [2])
            ).map(\.id) == [2]
        )
    }

    @Test("Exact and descendant tag matching use accepted effective tags only")
    func tagMatching() throws {
        let fixture = try tagFixture()
        let exact = group(
            .all,
            [
                .condition(
                    condition(
                        field: .tag,
                        operator: .is,
                        value: .tag(id: fixture.ambient.id, scope: .exact)
                    )
                ),
            ]
        )
        let descendants = group(
            .all,
            [
                .condition(
                    condition(
                        field: .tag,
                        operator: .is,
                        value: .tag(id: fixture.genre.id, scope: .includeSubtags)
                    )
                ),
            ]
        )

        #expect(
            evaluator().evaluate(
                root: exact,
                tracks: fixture.tracks,
                context: fixture.context
            ).map(\.id) == [1]
        )
        #expect(
            evaluator().evaluate(
                root: descendants,
                tracks: fixture.tracks,
                context: fixture.context
            ).map(\.id) == [1, 2, 3]
        )
    }

    @Test("A taxonomy candidate without an accepted effective assignment does not match")
    func suggestionsAreNotAssignments() throws {
        let ambient = try #require(TagPreview(path: "genre/ambient"))
        let root = group(
            .all,
            [
                .condition(
                    condition(
                        field: .tag,
                        operator: .is,
                        value: .tag(id: ambient.id, scope: .exact)
                    )
                ),
            ]
        )

        #expect(
            evaluator().evaluate(
                root: root,
                tracks: [track(id: 1)],
                context: context(
                    effectiveTags: [:],
                    taxonomy: [ambient]
                )
            ).isEmpty
        )
    }
}

private extension SmartCollectionRuleEvaluatorTests {
    func evaluator() -> SmartCollectionRuleEvaluator {
        SmartCollectionRuleEvaluator()
    }

    func group(
        _ combinator: SmartCollectionRuleCombinator,
        _ children: [SmartCollectionRuleNode]
    ) -> SmartCollectionRuleGroup {
        SmartCollectionRuleGroup(
            combinator: combinator,
            children: children
        )
    }

    func condition(
        field: SmartCollectionRuleField,
        operator: SmartCollectionRuleOperator,
        value: SmartCollectionRuleValue
    ) -> SmartCollectionRuleCondition {
        SmartCollectionRuleCondition(
            field: field,
            operator: `operator`,
            value: value
        )
    }

    func context(
        favorites: Set<TrackPreview.ID> = [],
        effectiveTags: [TrackPreview.ID: [TagPreview]] = [:],
        taxonomy: [TagPreview] = []
    ) -> SmartCollectionEvaluationContext {
        SmartCollectionEvaluationContext(
            effectiveTagsByTrackID: effectiveTags,
            tagsByID: Dictionary(
                uniqueKeysWithValues: taxonomy.map { ($0.id, $0) }
            ),
            favoriteTrackIDs: favorites
        )
    }

    func track(
        id: Int,
        artist: String = "Artist",
        album: String = "Album",
        year: Int = 2026,
        rating: Int = 5
    ) -> TrackPreview {
        TrackPreview(
            id: id,
            title: "Track \(id)",
            artist: artist,
            album: album,
            discNumber: 1,
            trackNumber: id,
            year: year,
            format: id.isMultiple(of: 2) ? "ALAC" : "FLAC",
            bitDepth: 24,
            sampleRate: 96,
            duration: 240,
            fileSize: "80 MB",
            lastPlayed: nil,
            rating: rating,
            isFavorite: false,
            artworkPalette: .silver
        )
    }

    func tagFixture() throws -> SmartCollectionTagFixture {
        let genre = try #require(TagPreview(path: "genre"))
        let ambient = try #require(TagPreview(path: "genre/ambient"))
        let ambientDeep = try #require(TagPreview(path: "genre/ambient/drone"))
        let sibling = try #require(TagPreview(path: "genre/jazz"))
        let tracks = [track(id: 1), track(id: 2), track(id: 3)]
        let tagContext = context(
            effectiveTags: [
                1: [ambient],
                2: [ambientDeep],
                3: [sibling],
            ],
            taxonomy: [genre, ambient, ambientDeep, sibling]
        )
        return SmartCollectionTagFixture(
            genre: genre,
            ambient: ambient,
            tracks: tracks,
            context: tagContext
        )
    }
}

private struct SmartCollectionTagFixture {
    let genre: TagPreview
    let ambient: TagPreview
    let tracks: [TrackPreview]
    let context: SmartCollectionEvaluationContext
}

private extension SmartCollectionRuleCondition {
    func negated() -> Self {
        var copy = self
        copy.isNegated.toggle()
        return copy
    }
}
