@testable import Cadence
import Foundation

extension [TrackPreview] {
    static let mockLibrary: [TrackPreview] = [
        mockTrack(1, "Midnight Static", "North Assembly", "Signals After Dark", 277, .blueHour),
        mockTrack(2, "Glass Horizon", "North Assembly", "Signals After Dark", 242, .blueHour),
        mockTrack(3, "Transmission Lines", "North Assembly", "Signals After Dark", 281, .blueHour),
        mockTrack(4, "Fade in the Distance", "North Assembly", "Signals After Dark", 232, .blueHour),
        mockTrack(5, "Hollow Frequency", "North Assembly", "Signals After Dark", 271, .blueHour),
        mockTrack(6, "Afterimage", "North Assembly", "Signals After Dark", 238, .blueHour),
        mockTrack(7, "Distant Satellites", "North Assembly", "Signals After Dark", 267, .blueHour),
        mockTrack(8, "Static Bloom", "North Assembly", "Signals After Dark", 250, .blueHour),
        mockTrack(9, "Quiet Return", "North Assembly", "Signals After Dark", 259, .blueHour),
        mockTrack(10, "Night Windows", "North Assembly", "Signals After Dark", 275, .blueHour),
        mockTrack(11, "Falling Signals", "North Assembly", "Signals After Dark", 243, .blueHour),
        mockTrack(12, "Approaching Light", "North Assembly", "Signals After Dark", 264, .blueHour),
        mockTrack(13, "Night Drive", "North Assembly", "Midnight Static", 252, .ember),
        mockTrack(14, "Echoes in Reverse", "North Assembly", "Midnight Static", 286, .ember),
        mockTrack(15, "Coastal Machines", "North Assembly", "Coastal Machines", 311, .silver),
        mockTrack(16, "Breakwater", "North Assembly", "Coastal Machines", 228, .silver),
        mockTrack(17, "Transient Lines", "North Assembly", "Transient Lines", 295, .amberNoir),
        mockTrack(18, "Relay State", "North Assembly", "Transient Lines", 247, .amberNoir),
        mockTrack(19, "Slow Geometry", "Mara Vale", "Quiet Machines", 249, .rose),
        mockTrack(20, "Quiet Machines", "Mara Vale", "Quiet Machines", 268, .amberNoir),
        mockTrack(21, "After the Rain", "Glass District", "Pale Signals", 315, .ocean),
        mockTrack(22, "Pale Signals", "Glass District", "Pale Signals", 222, .silver),
        mockTrack(23, "Faint Memory", "Soft Archive", "Recovered Light", 361, .lilac),
        mockTrack(24, "Paper Trails", "Soft Archive", "Recovered Light", 337, .lilac),
        mockTrack(25, "Winterlight", "Still North", "White Rooms", 238, .silver),
        mockTrack(26, "Weatherglass", "Still North", "White Rooms", 219, .forest),
        mockTrack(27, "Echoes Drift", "Nacre", "Low Tide", 411, nil),
        mockTrack(28, "Distant Bloom", "Iris Static", "False Spring", 253, .rose),
        mockTrack(29, "Sleepless City", "Neon Census", "Windows at 3 AM", 306, .sunset),
        mockTrack(30, "Hollow Lights", "Relay", "Structures", 284, .amberNoir),
        mockTrack(31, "Blue Hours", "Kite Theory", "Nocturnes for Empty Roads", 294, .arctic),
    ]

    // A positional seed keeps the mock catalog readable as a compact album sequence.
    // swiftlint:disable:next function_parameter_count
    private static func mockTrack(
        _ id: Int,
        _ title: String,
        _ artist: String,
        _ album: String,
        _ duration: TimeInterval,
        _ palette: ArtworkPalette?
    ) -> TrackPreview {
        let year = artist == "North Assembly" ? 2026 : 2024
        return TrackPreview(
            id: id,
            title: title,
            artist: artist,
            album: album,
            discNumber: 1,
            trackNumber: mockTrackNumber(id),
            year: year,
            format: id.isMultiple(of: 5) ? "ALAC" : "FLAC",
            bitDepth: 24,
            sampleRate: id.isMultiple(of: 3) ? 48 : 96,
            duration: duration,
            fileSize: "\(58 + id * 3).\(id % 10) MB",
            lastPlayed: id.isMultiple(of: 4) ? nil : mockDate(daysAgo: Swift.max(id - 2, 1)),
            rating: id.isMultiple(of: 4) ? 4 : 5,
            isFavorite: favoriteTrackIDs.contains(id),
            artworkPalette: palette
        )
    }

    private static func mockTrackNumber(_ id: Int) -> Int {
        switch id {
        case 1 ... 12:
            id
        case 13 ... 14:
            id - 12
        case 15 ... 16:
            id - 14
        case 17 ... 18:
            id - 16
        case 19 ... 20:
            id - 18
        case 21 ... 22:
            id - 20
        case 23 ... 24:
            id - 22
        case 25 ... 26:
            id - 24
        default:
            1
        }
    }

    private static let favoriteTrackIDs: Set<Int> = [1, 21, 23, 25, 29]

    private static func mockDate(daysAgo: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -daysAgo,
            to: Date(timeIntervalSince1970: 1_784_894_400)
        ) ?? Date(timeIntervalSince1970: 1_784_894_400)
    }
}
