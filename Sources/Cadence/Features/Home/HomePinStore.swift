import Foundation

enum HomePinKind: String, CaseIterable, Sendable {
    case album
    case artist
    case playlist

    var storageKey: String {
        "home.pins.\(rawValue)"
    }
}

enum HomePinnedSectionKind: Equatable, Sendable {
    case albums
    case artists
    case playlists

    var title: String {
        switch self {
        case .albums: "Pinned Albums"
        case .artists: "Pinned Artists"
        case .playlists: "Pinned Playlists"
        }
    }

    static func visibleKinds(
        albumCount: Int,
        artistCount: Int,
        playlistCount: Int
    ) -> [HomePinnedSectionKind] {
        [
            albumCount > 0 ? .albums : nil,
            artistCount > 0 ? .artists : nil,
            playlistCount > 0 ? .playlists : nil,
        ].compactMap(\.self)
    }
}

enum HomePinStore {
    static func contains(_ id: UUID, in kind: HomePinKind) -> Bool {
        identifiers(for: kind).contains(id)
    }

    static func toggle(_ id: UUID, in kind: HomePinKind) {
        var ids = identifiers(for: kind)
        if !ids.insert(id).inserted {
            ids.remove(id)
        }
        save(ids, for: kind)
    }

    static func orderedIDs(for kind: HomePinKind) -> [UUID] {
        UserDefaults.standard.stringArray(forKey: kind.storageKey)?
            .compactMap(UUID.init(uuidString:)) ?? []
    }

    static func orderedItems<Item: Identifiable>(
        ids: [UUID],
        source: [Item]
    ) -> [Item] where Item.ID == UUID {
        var itemsByID: [UUID: Item] = [:]
        for item in source where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }

        var seen = Set<UUID>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else {
                return nil
            }
            return itemsByID[id]
        }
    }

    private static func identifiers(for kind: HomePinKind) -> Set<UUID> {
        Set(orderedIDs(for: kind))
    }

    private static func save(_ ids: Set<UUID>, for kind: HomePinKind) {
        let preservedOrder = orderedIDs(for: kind).filter(ids.contains)
        let appended = ids.subtracting(preservedOrder).sorted {
            $0.uuidString < $1.uuidString
        }
        UserDefaults.standard.set(
            (preservedOrder + appended).map(\.uuidString),
            forKey: kind.storageKey
        )
        UserDefaults.standard.set(
            UserDefaults.standard.integer(forKey: "home.pins.revision") + 1,
            forKey: "home.pins.revision"
        )
    }
}

enum HomeFavoriteRecencyStore {
    private static let trackKey = "home.favoriteTrackRecency"

    static func recordTrack(
        _ id: UUID,
        isFavorite: Bool,
        defaults: UserDefaults = .standard
    ) {
        var ids = orderedTrackIDs(defaults: defaults).filter { $0 != id }
        if isFavorite {
            ids.insert(id, at: 0)
        }
        defaults.set(ids.map(\.uuidString), forKey: trackKey)
    }

    static func orderedTracks(
        _ tracks: [LibraryTrackProjection],
        defaults: UserDefaults = .standard
    ) -> [LibraryTrackProjection] {
        let rank = Dictionary(
            uniqueKeysWithValues: orderedTrackIDs(defaults: defaults).enumerated().map {
                ($0.element, $0.offset)
            }
        )
        return tracks.enumerated().sorted { lhs, rhs in
            let lhsRank = rank[lhs.element.id] ?? Int.max
            let rhsRank = rank[rhs.element.id] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func orderedTrackIDs(defaults: UserDefaults) -> [UUID] {
        defaults.stringArray(forKey: trackKey)?
            .compactMap(UUID.init(uuidString:)) ?? []
    }
}
