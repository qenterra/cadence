import Foundation

struct PlaybackSessionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let source: PlaybackQueueSource
    let orderedTrackIDs: [UUID]
    let currentTrackID: UUID
    let isShuffled: Bool
    let repeatMode: RepeatMode
    let canonicalTrackIDs: [UUID]
    let currentTime: TimeInterval

    init(
        queue: PlaybackQueueState,
        repeatMode: RepeatMode,
        canonicalTrackIDs: [UUID],
        currentTime: TimeInterval
    ) {
        schemaVersion = Self.currentSchemaVersion
        source = queue.source
        orderedTrackIDs = queue.orderedTrackIDs
        currentTrackID = queue.currentTrackID ?? UUID()
        isShuffled = queue.isShuffled
        self.repeatMode = repeatMode
        self.canonicalTrackIDs = canonicalTrackIDs
        self.currentTime = max(currentTime, 0)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case source
        case orderedTrackIDs
        case currentTrackID
        case isShuffled
        case repeatMode
        case canonicalTrackIDs
        case currentTime
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        source = try container.decode(PlaybackQueueSource.self, forKey: .source)
        orderedTrackIDs = try container.decode(
            [UUID].self,
            forKey: .orderedTrackIDs
        )
        currentTrackID = try container.decode(UUID.self, forKey: .currentTrackID)
        isShuffled = try container.decode(Bool.self, forKey: .isShuffled)
        repeatMode = try container.decodeIfPresent(
            RepeatMode.self,
            forKey: .repeatMode
        ) ?? .off
        canonicalTrackIDs = try container.decode(
            [UUID].self,
            forKey: .canonicalTrackIDs
        )
        currentTime = try container.decode(
            TimeInterval.self,
            forKey: .currentTime
        )
    }

    func restoredState(
        validTrackIDs: Set<UUID>
    ) -> (queue: PlaybackQueueState, canonicalTrackIDs: [UUID])? {
        guard schemaVersion == Self.currentSchemaVersion,
              source != .externalFiles,
              currentTime.isFinite,
              currentTime >= 0,
              validTrackIDs.contains(currentTrackID)
        else {
            return nil
        }
        let order = unique(orderedTrackIDs.filter(validTrackIDs.contains))
        guard order.contains(currentTrackID) else {
            return nil
        }
        let canonical = unique(
            canonicalTrackIDs.filter(validTrackIDs.contains)
        )
        let canonicalWithMissing = canonical + order.filter {
            !canonical.contains($0)
        }
        return (
            PlaybackQueueState(
                source: source,
                orderedTrackIDs: order,
                startingAt: currentTrackID,
                isShuffled: isShuffled
            ),
            canonicalWithMissing
        )
    }

    private func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}

struct PlaybackSessionStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ snapshot: PlaybackSessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: CadencePreferences.Keys.playbackSession)
    }

    func load() -> PlaybackSessionSnapshot? {
        guard
            let data = defaults.data(
                forKey: CadencePreferences.Keys.playbackSession
            ),
            let snapshot = try? JSONDecoder().decode(
                PlaybackSessionSnapshot.self,
                from: data
            ),
            snapshot.schemaVersion == PlaybackSessionSnapshot.currentSchemaVersion
        else {
            clear()
            return nil
        }
        return snapshot
    }

    func clear() {
        defaults.removeObject(forKey: CadencePreferences.Keys.playbackSession)
    }
}
