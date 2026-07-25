import Foundation

extension [AlbumPreview.ID: Date] {
    static var mockAlbumFavorites: Self {
        [
            "North Assembly\u{1F}Signals After Dark": mockFavoriteDate(daysAgo: 1),
            "Glass District\u{1F}Pale Signals": mockFavoriteDate(daysAgo: 4),
            "Soft Archive\u{1F}Recovered Light": mockFavoriteDate(daysAgo: 9),
        ]
    }

    private static func mockFavoriteDate(daysAgo: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -daysAgo,
            to: Date(timeIntervalSince1970: 1_784_894_400)
        ) ?? Date(timeIntervalSince1970: 1_784_894_400)
    }
}
