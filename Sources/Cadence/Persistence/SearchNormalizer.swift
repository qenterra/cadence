import Foundation

enum SearchNormalizer {
    private static let stableLocale = Locale(identifier: "en_US_POSIX")

    static func normalize(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive,
                ],
                locale: stableLocale
            )
            .lowercased(with: stableLocale)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
