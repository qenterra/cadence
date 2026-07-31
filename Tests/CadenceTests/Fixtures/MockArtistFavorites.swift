@testable import Cadence
import Foundation

extension [ArtistPreview.ID: Date] {
    static var mockArtistFavorites: Self {
        [
            "North Assembly": Date(timeIntervalSince1970: 1_784_808_000),
            "Glass District": Date(timeIntervalSince1970: 1_784_721_600),
            "Still North": Date(timeIntervalSince1970: 1_784_635_200),
        ]
    }
}
