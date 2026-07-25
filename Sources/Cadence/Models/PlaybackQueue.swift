import Foundation

struct PlaybackQueue: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case album(AlbumPreview.ID)
        case smartCollection(SmartCollectionPreview.ID)
        case adHoc
    }

    let source: Source
    private(set) var orderedTrackIDs: [TrackPreview.ID]
    private(set) var currentIndex: Int
    let isShuffled: Bool

    init(
        source: Source,
        orderedTrackIDs: [TrackPreview.ID],
        startingAt trackID: TrackPreview.ID? = nil,
        isShuffled: Bool = false
    ) {
        self.source = source
        self.orderedTrackIDs = orderedTrackIDs.reduce(into: []) { result, id in
            if !result.contains(id) {
                result.append(id)
            }
        }
        currentIndex = self.orderedTrackIDs.firstIndex {
            $0 == trackID
        } ?? 0
        self.isShuffled = isShuffled
    }

    var currentTrackID: TrackPreview.ID? {
        guard orderedTrackIDs.indices.contains(currentIndex) else {
            return nil
        }
        return orderedTrackIDs[currentIndex]
    }

    var previouslyPlayedTrackIDs: [TrackPreview.ID] {
        guard orderedTrackIDs.indices.contains(currentIndex) else {
            return []
        }
        return Array(orderedTrackIDs[..<currentIndex])
    }

    var upNextTrackIDs: [TrackPreview.ID] {
        guard orderedTrackIDs.indices.contains(currentIndex) else {
            return []
        }
        return Array(orderedTrackIDs.dropFirst(currentIndex + 1))
    }

    mutating func move(
        by offset: Int,
        availableTrackIDs: Set<TrackPreview.ID>
    ) -> TrackPreview.ID? {
        guard !orderedTrackIDs.isEmpty else {
            return nil
        }

        for step in 1 ... orderedTrackIDs.count {
            let distance = offset * step
            let candidateIndex = (
                currentIndex + distance + orderedTrackIDs.count * step
            ) % orderedTrackIDs.count
            let candidateID = orderedTrackIDs[candidateIndex]
            if availableTrackIDs.contains(candidateID) {
                currentIndex = candidateIndex
                return candidateID
            }
        }
        return nil
    }

    @discardableResult
    mutating func reorderUpNext(
        _ movingTrackIDs: [TrackPreview.ID],
        before targetTrackID: TrackPreview.ID?
    ) -> Bool {
        let currentUpNext = upNextTrackIDs
        let movingSet = Set(movingTrackIDs)
        let moving = currentUpNext.filter(movingSet.contains)
        guard !moving.isEmpty else {
            return false
        }

        var remaining = currentUpNext.filter { !movingSet.contains($0) }
        let insertionIndex = targetTrackID.flatMap { target in
            remaining.firstIndex(of: target)
        } ?? remaining.endIndex
        remaining.insert(contentsOf: moving, at: insertionIndex)
        guard remaining != currentUpNext else {
            return false
        }

        replaceUpNext(with: remaining)
        return true
    }

    @discardableResult
    mutating func removeUpNext(
        _ trackIDs: [TrackPreview.ID]
    ) -> Bool {
        let removal = Set(trackIDs)
        let updated = upNextTrackIDs.filter { !removal.contains($0) }
        guard updated != upNextTrackIDs else {
            return false
        }
        replaceUpNext(with: updated)
        return true
    }

    @discardableResult
    mutating func clearUpNext() -> Bool {
        guard !upNextTrackIDs.isEmpty else {
            return false
        }
        replaceUpNext(with: [])
        return true
    }

    @discardableResult
    mutating func playNext(
        _ trackIDs: [TrackPreview.ID]
    ) -> Bool {
        let unavailable = Set(
            previouslyPlayedTrackIDs + [currentTrackID].compactMap(\.self)
        )
        let requested = trackIDs.reduce(into: [TrackPreview.ID]()) { result, trackID in
            guard
                !unavailable.contains(trackID),
                !result.contains(trackID)
            else {
                return
            }
            result.append(trackID)
        }
        guard !requested.isEmpty else {
            return false
        }

        let requestedSet = Set(requested)
        let remaining = upNextTrackIDs.filter {
            !requestedSet.contains($0)
        }
        let updated = requested + remaining
        guard updated != upNextTrackIDs else {
            return false
        }
        replaceUpNext(with: updated)
        return true
    }

    @discardableResult
    mutating func addToEnd(
        _ trackIDs: [TrackPreview.ID]
    ) -> Bool {
        let existing = Set(orderedTrackIDs)
        let appended = trackIDs.reduce(into: [TrackPreview.ID]()) { result, trackID in
            guard
                !existing.contains(trackID),
                !result.contains(trackID)
            else {
                return
            }
            result.append(trackID)
        }
        guard !appended.isEmpty else {
            return false
        }
        replaceUpNext(with: upNextTrackIDs + appended)
        return true
    }

    static func shuffledOrder(
        _ trackIDs: [TrackPreview.ID],
        using generator: inout some RandomNumberGenerator
    ) -> [TrackPreview.ID] {
        trackIDs.shuffled(using: &generator)
    }

    private mutating func replaceUpNext(
        with trackIDs: [TrackPreview.ID]
    ) {
        let previous = previouslyPlayedTrackIDs
        guard let currentTrackID else {
            return
        }
        orderedTrackIDs = previous + [currentTrackID] + trackIDs
        currentIndex = previous.count
    }
}
