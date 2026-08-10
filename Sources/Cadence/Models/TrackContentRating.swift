import Foundation

enum TrackContentRating {
    static func isExplicit(sourceMetadata: Data?) -> Bool {
        guard
            let sourceMetadata,
            let snapshot = try? JSONDecoder().decode(
                SourceMetadataSnapshot.self,
                from: sourceMetadata
            )
        else {
            return false
        }

        return snapshot.items.contains { item in
            let hasRatingKey = [
                item.identifier,
                item.rawKey,
                item.canonicalKey,
            ]
            .compactMap(\.self)
            .contains(where: isExplicitRatingKey)
            guard hasRatingKey else {
                return false
            }
            let value = item.stringValue?.lowercased() ?? ""
            return value.contains("explicit")
                || value.contains("contentwarning")
                || value == "1"
                || item.numberValue == 1
        }
    }

    private static func isExplicitRatingKey(_ key: String) -> Bool {
        let normalizedKey = key.lowercased().filter(\.isLetter)
        return explicitRatingKeys.contains(normalizedKey)
            || explicitRatingKeys.contains {
                normalizedKey.hasSuffix($0)
            }
    }

    private static let explicitRatingKeys: Set<String> = [
        "advisory",
        "commonidentifiercontentrating",
        "contentrating",
        "explicit",
        "itunescontentrating",
        "itunesadvisory",
        "itunesextc",
        "rating",
        "rtng",
    ]
}
