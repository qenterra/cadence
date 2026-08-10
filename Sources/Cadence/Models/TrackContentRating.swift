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
            let key = [item.identifier, item.rawKey, item.canonicalKey]
                .compactMap(\.self)
                .joined(separator: " ")
                .lowercased()
                .filter(\.isLetter)
            guard explicitRatingKeys.contains(key) else {
                return false
            }
            let value = item.stringValue?.lowercased() ?? ""
            return value.contains("explicit")
                || value.contains("contentwarning")
                || value == "1"
                || item.numberValue == 1
        }
    }

    private static let explicitRatingKeys: Set<String> = [
        "advisory",
        "contentrating",
        "explicit",
        "itunescontentrating",
        "itunesadvisory",
        "itunesextc",
        "rating",
    ]
}
