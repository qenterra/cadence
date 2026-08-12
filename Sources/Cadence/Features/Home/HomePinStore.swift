import Foundation

enum HomePinKind: String, CaseIterable, Sendable {
    case album
    case artist
    case playlist
    case smartCollection

    var storageKey: String {
        "home.pins.\(rawValue)"
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
