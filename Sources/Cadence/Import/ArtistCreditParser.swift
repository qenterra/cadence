import Foundation

struct ArtistCreditParser: Sendable {
    private static let featuringExpression: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"(?i)\s+(?:feat(?:uring)?|ft)\.?\s+"#
            )
        } catch {
            preconditionFailure(
                "The built-in artist-credit expression must compile: \(error)"
            )
        }
    }()

    func parse(
        values: [String],
        fallback: String
    ) -> [String] {
        var artists: [String] = []
        var seen: Set<String> = []

        for value in values {
            let range = NSRange(value.startIndex ..< value.endIndex, in: value)
            let normalizedSeparators = Self.featuringExpression
                .stringByReplacingMatches(
                    in: value,
                    range: range,
                    withTemplate: ";"
                )
            for component in normalizedSeparators.components(
                separatedBy: CharacterSet(charactersIn: ",;")
            ) {
                let artist = component.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !artist.isEmpty else {
                    continue
                }
                let identity = SearchNormalizer.normalize(artist)
                guard seen.insert(identity).inserted else {
                    continue
                }
                artists.append(artist)
            }
        }

        if artists.isEmpty {
            let trimmedFallback = fallback.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return [trimmedFallback.isEmpty ? "Unknown Artist" : trimmedFallback]
        }
        return artists
    }
}
