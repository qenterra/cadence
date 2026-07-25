import Foundation

extension [SmartCollectionPreview] {
    static let mockSmartCollections: [SmartCollectionPreview] = [
        SmartCollectionPreview(
            id: mockID(1),
            name: "Night Signals",
            rule: SmartCollectionRuleGroup(
                id: mockID(11),
                combinator: .all,
                children: [
                    .condition(
                        SmartCollectionRuleCondition(
                            id: mockID(12),
                            field: .tag,
                            operator: .is,
                            value: .tag(
                                id: "context/night",
                                scope: .exact
                            )
                        )
                    ),
                    .condition(
                        SmartCollectionRuleCondition(
                            id: mockID(13),
                            field: .format,
                            operator: .is,
                            value: .text("FLAC")
                        )
                    ),
                ]
            ),
            modifiedAt: mockDate
        ),
        SmartCollectionPreview(
            id: mockID(2),
            name: "Quiet Favorites",
            rule: SmartCollectionRuleGroup(
                id: mockID(21),
                combinator: .all,
                children: [
                    .condition(
                        SmartCollectionRuleCondition(
                            id: mockID(22),
                            field: .favorite,
                            operator: .is,
                            value: .boolean(true)
                        )
                    ),
                    .condition(
                        SmartCollectionRuleCondition(
                            id: mockID(23),
                            field: .rating,
                            operator: .greaterThan,
                            value: .integer(4)
                        )
                    ),
                ]
            ),
            modifiedAt: mockDate
        ),
        SmartCollectionPreview(
            id: mockID(3),
            name: "Focus or Calm",
            rule: SmartCollectionRuleGroup(
                id: mockID(31),
                combinator: .all,
                children: [
                    .condition(
                        SmartCollectionRuleCondition(
                            id: mockID(32),
                            field: .format,
                            operator: .contains,
                            value: .text("FLAC")
                        )
                    ),
                    .group(
                        SmartCollectionRuleGroup(
                            id: mockID(33),
                            combinator: .any,
                            children: [
                                .condition(
                                    SmartCollectionRuleCondition(
                                        id: mockID(34),
                                        field: .tag,
                                        operator: .is,
                                        value: .tag(
                                            id: "context/focus",
                                            scope: .exact
                                        )
                                    )
                                ),
                                .condition(
                                    SmartCollectionRuleCondition(
                                        id: mockID(35),
                                        field: .tag,
                                        operator: .is,
                                        value: .tag(
                                            id: "mood/calm",
                                            scope: .exact
                                        )
                                    )
                                ),
                            ]
                        )
                    ),
                ]
            ),
            modifiedAt: mockDate
        ),
    ]

    private static let mockDate = Date(timeIntervalSince1970: 1_785_000_000)

    private static func mockID(_ value: UInt32) -> UUID {
        UUID(
            uuidString: String(
                format: "CA000000-0000-0000-0000-%012X",
                value
            )
        ) ?? UUID()
    }
}
