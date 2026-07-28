import Foundation

struct PlaybackQueueState: Equatable, Sendable {
    let source: PlaybackQueueSource
    private(set) var orderedTrackIDs: [UUID]
    private(set) var currentIndex: Int
    private(set) var isShuffled: Bool

    init(
        source: PlaybackQueueSource,
        orderedTrackIDs: [UUID],
        startingAt trackID: UUID?,
        isShuffled: Bool = false
    ) {
        self.source = source
        self.orderedTrackIDs = orderedTrackIDs.reduce(into: []) { result, id in
            if !result.contains(id) {
                result.append(id)
            }
        }
        currentIndex = self.orderedTrackIDs.firstIndex(of: trackID ?? UUID())
            ?? 0
        self.isShuffled = isShuffled
    }

    var currentTrackID: UUID? {
        guard orderedTrackIDs.indices.contains(currentIndex) else {
            return nil
        }
        return orderedTrackIDs[currentIndex]
    }

    var previouslyPlayedTrackIDs: [UUID] {
        guard orderedTrackIDs.indices.contains(currentIndex) else {
            return []
        }
        return Array(orderedTrackIDs[..<currentIndex])
    }

    var upNextTrackIDs: [UUID] {
        guard orderedTrackIDs.indices.contains(currentIndex) else {
            return []
        }
        return Array(orderedTrackIDs.dropFirst(currentIndex + 1))
    }

    mutating func move(
        by offset: Int,
        wrapping: Bool,
        excluding excludedIDs: Set<UUID> = []
    ) -> UUID? {
        guard !orderedTrackIDs.isEmpty, offset != 0 else {
            return currentTrackID
        }

        var candidateIndex = currentIndex
        for _ in orderedTrackIDs.indices {
            candidateIndex += offset.signum()
            if !orderedTrackIDs.indices.contains(candidateIndex) {
                guard wrapping else {
                    return nil
                }
                candidateIndex = offset > 0
                    ? orderedTrackIDs.startIndex
                    : orderedTrackIDs.index(before: orderedTrackIDs.endIndex)
            }

            let candidateID = orderedTrackIDs[candidateIndex]
            if !excludedIDs.contains(candidateID) {
                currentIndex = candidateIndex
                return candidateID
            }
        }
        return nil
    }

    mutating func move(to trackID: UUID) -> Bool {
        guard let index = orderedTrackIDs.firstIndex(of: trackID) else {
            return false
        }
        currentIndex = index
        return true
    }

    mutating func replaceOrder(
        _ trackIDs: [UUID],
        currentTrackID: UUID
    ) {
        let unique = trackIDs.reduce(into: [UUID]()) { result, id in
            if !result.contains(id) {
                result.append(id)
            }
        }
        guard let currentIndex = unique.firstIndex(of: currentTrackID) else {
            return
        }
        orderedTrackIDs = unique
        self.currentIndex = currentIndex
    }

    mutating func setShuffled(
        _ shuffled: Bool,
        using generator: inout some RandomNumberGenerator
    ) {
        guard shuffled != isShuffled, let currentTrackID else {
            return
        }
        if shuffled {
            let history = previouslyPlayedTrackIDs
            let upcoming = upNextTrackIDs.shuffled(using: &generator)
            orderedTrackIDs = history + [currentTrackID] + upcoming
            currentIndex = history.count
        }
        isShuffled = shuffled
    }

    @discardableResult
    mutating func reorderUpNext(
        _ movingTrackIDs: [UUID],
        before targetTrackID: UUID?
    ) -> Bool {
        let currentUpNext = upNextTrackIDs
        let movingSet = Set(movingTrackIDs)
        let moving = currentUpNext.filter(movingSet.contains)
        guard !moving.isEmpty else {
            return false
        }

        var remaining = currentUpNext.filter { !movingSet.contains($0) }
        let insertionIndex = targetTrackID.flatMap(remaining.firstIndex)
            ?? remaining.endIndex
        remaining.insert(contentsOf: moving, at: insertionIndex)
        return replaceUpNextIfChanged(remaining)
    }

    @discardableResult
    mutating func removeUpNext(_ trackIDs: [UUID]) -> Bool {
        let removal = Set(trackIDs)
        return replaceUpNextIfChanged(
            upNextTrackIDs.filter { !removal.contains($0) }
        )
    }

    @discardableResult
    mutating func clearUpNext() -> Bool {
        replaceUpNextIfChanged([])
    }

    @discardableResult
    mutating func playNext(_ trackIDs: [UUID]) -> Bool {
        let fixed = Set(
            previouslyPlayedTrackIDs + [currentTrackID].compactMap(\.self)
        )
        let requested = trackIDs.reduce(into: [UUID]()) { result, id in
            if !fixed.contains(id), !result.contains(id) {
                result.append(id)
            }
        }
        guard !requested.isEmpty else {
            return false
        }
        let requestedSet = Set(requested)
        return replaceUpNextIfChanged(
            requested + upNextTrackIDs.filter { !requestedSet.contains($0) }
        )
    }

    @discardableResult
    mutating func addToEnd(_ trackIDs: [UUID]) -> Bool {
        let existing = Set(orderedTrackIDs)
        let additions = trackIDs.reduce(into: [UUID]()) { result, id in
            if !existing.contains(id), !result.contains(id) {
                result.append(id)
            }
        }
        guard !additions.isEmpty else {
            return false
        }
        return replaceUpNextIfChanged(upNextTrackIDs + additions)
    }

    private mutating func replaceUpNextIfChanged(
        _ replacement: [UUID]
    ) -> Bool {
        guard replacement != upNextTrackIDs, let currentTrackID else {
            return false
        }
        let history = previouslyPlayedTrackIDs
        orderedTrackIDs = history + [currentTrackID] + replacement
        currentIndex = history.count
        return true
    }
}
