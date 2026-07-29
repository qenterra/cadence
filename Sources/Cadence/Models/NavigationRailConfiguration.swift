import Foundation

enum NavigationRailConfiguration {
    static let configurableDestinations: [NavigationDestination] = [
        .library,
        .allTracks,
        .albums,
        .artists,
        .tags,
        .smartCollections,
        .playlists,
        .importMusic,
    ]

    static var defaultOrderRawValue: String {
        encode(configurableDestinations)
    }

    static func orderedDestinations(
        from rawValue: String
    ) -> [NavigationDestination] {
        let allowed = Set(configurableDestinations)
        let decoded = rawValue
            .split(separator: ",")
            .compactMap { NavigationDestination(rawValue: String($0)) }
            .filter(allowed.contains)
        var seen = Set<NavigationDestination>()
        let unique = decoded.filter { seen.insert($0).inserted }
        return unique + configurableDestinations.filter {
            !seen.contains($0)
        }
    }

    static func hiddenDestinations(
        from rawValue: String
    ) -> Set<NavigationDestination> {
        let allowed = Set(configurableDestinations)
        return Set(
            rawValue
                .split(separator: ",")
                .compactMap {
                    NavigationDestination(rawValue: String($0))
                }
                .filter(allowed.contains)
        )
    }

    static func visibleDestinations(
        orderRawValue: String,
        hiddenRawValue: String
    ) -> [NavigationDestination] {
        let hidden = hiddenDestinations(from: hiddenRawValue)
        return orderedDestinations(from: orderRawValue).filter {
            !hidden.contains($0)
        }
    }

    static func encode(
        _ destinations: some Sequence<NavigationDestination>
    ) -> String {
        destinations.map(\.rawValue).joined(separator: ",")
    }
}
