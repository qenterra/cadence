import Foundation

struct TrackRowDisplayProjection: Equatable, Sendable {
    let id: UUID
    let artistID: UUID?
    let albumID: UUID?
    let artworkRequest: ProductionArtworkRequest
    let title: String
    let artist: String
    let album: String
    let codec: String
    let year: String
    let duration: String
    let isFavorite: Bool
    let isExplicit: Bool
    let hasSynchronizedLyrics: Bool
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let accessibilityLabel: String

    init(
        track: LibraryTrackProjection,
        isCurrentTrack: Bool,
        isPlaying: Bool
    ) {
        id = track.id
        artistID = track.artistID
        albumID = track.albumID
        artworkRequest = ProductionArtworkRequest(
            artworkID: track.artworkID,
            variant: .trackRow
        )
        title = Self.displayText(
            track.title,
            fallback: String(localized: "Untitled Track")
        )
        artist = Self.displayText(
            track.artist,
            fallback: String(localized: "Unknown Artist")
        )
        album = Self.displayText(
            track.album,
            fallback: String(localized: "Unknown Album")
        )
        codec = Self.codecText(track.codec)
        year = track.year.map(String.init) ?? "—"
        duration = Self.durationText(track.duration)
        isFavorite = track.isFavorite
        isExplicit = track.isExplicit
        hasSynchronizedLyrics = track.hasSynchronizedLyrics
        self.isCurrentTrack = isCurrentTrack
        self.isPlaying = isCurrentTrack && isPlaying
        accessibilityLabel = [title, artist, album, duration]
            .joined(separator: ", ")
    }

    private static func displayText(
        _ value: String,
        fallback: String
    ) -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func codecText(_ codec: String) -> String {
        let normalized = codec
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "." })
            .uppercased()
        return normalized.isEmpty ? "—" : normalized
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

enum NativeTrackTableContent: Equatable, Sendable {
    case placeholder
    case track(TrackRowDisplayProjection)
}

@MainActor
final class TrackRowDisplayProjectionCache {
    private struct Entry {
        let track: LibraryTrackProjection
        let isCurrentTrack: Bool
        let isPlaying: Bool
        let projection: TrackRowDisplayProjection
    }

    private let capacity: Int
    private let probe: TrackTableWorkProbe?
    private var entries: [UUID: Entry] = [:]
    private var evictionSlots: [UUID?]
    private var nextEvictionSlot = 0

    init(
        capacity: Int = 384,
        probe: TrackTableWorkProbe? = nil
    ) {
        self.capacity = max(capacity, 1)
        self.probe = probe
        evictionSlots = Array(
            repeating: nil,
            count: self.capacity
        )
    }

    func resolve(
        track: LibraryTrackProjection,
        currentTrackID: UUID?,
        isCurrentTrackPlaying: Bool
    ) -> TrackRowDisplayProjection {
        let isCurrentTrack = track.id == currentTrackID
        let isPlaying = isCurrentTrack && isCurrentTrackPlaying
        if let entry = entries[track.id],
           entry.track == track,
           entry.isCurrentTrack == isCurrentTrack,
           entry.isPlaying == isPlaying {
            probe?.recordDisplayProjectionCacheHit()
            return entry.projection
        }
        probe?.recordDisplayProjectionBuild()
        let projection = TrackRowDisplayProjection(
            track: track,
            isCurrentTrack: isCurrentTrack,
            isPlaying: isPlaying
        )
        insert(
            Entry(
                track: track,
                isCurrentTrack: isCurrentTrack,
                isPlaying: isPlaying,
                projection: projection
            ),
            for: track.id
        )
        return projection
    }

    var count: Int {
        entries.count
    }

    private func insert(_ entry: Entry, for id: UUID) {
        if entries[id] != nil {
            entries[id] = entry
            return
        }
        if let evictedID = evictionSlots[nextEvictionSlot] {
            entries.removeValue(forKey: evictedID)
        }
        evictionSlots[nextEvictionSlot] = id
        nextEvictionSlot = (nextEvictionSlot + 1) % capacity
        entries[id] = entry
    }
}
