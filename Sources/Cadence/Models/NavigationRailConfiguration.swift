import Foundation

enum NavigationRailConfiguration {
    static let defaultIsExpanded = true

    static let configurableDestinations: [NavigationDestination] = [
        .home,
        .favorites,
        .library,
        .allTracks,
        .albums,
        .artists,
        .playlists,
        .smartCollections,
        .tags,
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
        let unique = decoded.filter {
            $0 != .home && seen.insert($0).inserted
        }
        seen.insert(.home)
        return [.home] + unique + configurableDestinations.filter {
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

    static func visibleSections(
        orderRawValue: String,
        hiddenRawValue: String
    ) -> [NavigationRailSection] {
        let visible = visibleDestinations(
            orderRawValue: orderRawValue,
            hiddenRawValue: hiddenRawValue
        )
        return NavigationRailGroup.allCases.compactMap { group in
            let destinations = visible.filter {
                $0.navigationGroup == group
            }
            guard !destinations.isEmpty else {
                return nil
            }
            return NavigationRailSection(
                group: group,
                destinations: destinations
            )
        }
    }

    static func moving(
        _ source: NavigationDestination,
        to target: NavigationDestination,
        in destinations: [NavigationDestination]
    ) -> [NavigationDestination] {
        guard
            source != target,
            source != .home,
            let sourceIndex = destinations.firstIndex(of: source),
            let targetIndex = destinations.firstIndex(of: target)
        else {
            return destinations
        }

        var reordered = destinations
        let destination = reordered.remove(at: sourceIndex)
        let insertionIndex = target == .home
            ? min(1, reordered.endIndex)
            : min(targetIndex, reordered.endIndex)
        reordered.insert(
            destination,
            at: insertionIndex
        )
        if let homeIndex = reordered.firstIndex(of: .home), homeIndex != 0 {
            let home = reordered.remove(at: homeIndex)
            reordered.insert(home, at: 0)
        }
        return reordered
    }

    static func encode(
        _ destinations: some Sequence<NavigationDestination>
    ) -> String {
        destinations.map(\.rawValue).joined(separator: ",")
    }
}

struct NavigationRailSection: Equatable, Identifiable, Sendable {
    let group: NavigationRailGroup
    let destinations: [NavigationDestination]

    var id: NavigationRailGroup {
        group
    }
}
