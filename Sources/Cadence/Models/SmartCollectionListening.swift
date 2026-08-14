import Foundation

enum SmartCollectionsPresentationMode: Hashable, Sendable {
    case listening
    case editing
}

enum SmartCollectionSortField: String, CaseIterable, Hashable, Identifiable, Sendable {
    case canonical
    case title
    case artist
    case album
    case year
    case format
    case duration

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .canonical: "#"
        case .title: String(localized: "Title")
        case .artist: String(localized: "Artist")
        case .album: String(localized: "Album")
        case .year: String(localized: "Year")
        case .format: String(localized: "Format")
        case .duration: String(localized: "Time")
        }
    }
}

enum SmartCollectionSortDirection: Hashable, Sendable {
    case ascending
    case descending

    var toggled: Self {
        self == .ascending ? .descending : .ascending
    }
}

struct SmartCollectionSortDescriptor: Hashable, Sendable {
    var field: SmartCollectionSortField
    var direction: SmartCollectionSortDirection

    static let canonical = SmartCollectionSortDescriptor(
        field: .canonical,
        direction: .ascending
    )

    mutating func activate(_ newField: SmartCollectionSortField) {
        guard newField != .canonical else {
            self = .canonical
            return
        }

        if field == newField {
            direction = direction.toggled
        } else {
            field = newField
            direction = .ascending
        }
    }
}

struct SmartCollectionArtworkSlot: Hashable, Sendable {
    let albumID: AlbumPreview.ID
    let albumTitle: String
    let palette: ArtworkPalette?
}

struct SmartCollectionArtworkLayout: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case empty
        case single
        case split
        case trio
        case grid
    }

    let kind: Kind
    let slots: [SmartCollectionArtworkSlot]
}

enum SmartCollectionListeningProjection {
    static func sortedTracks(
        _ tracks: [TrackPreview],
        by descriptor: SmartCollectionSortDescriptor
    ) -> [TrackPreview] {
        guard descriptor.field != .canonical else {
            return tracks
        }

        let canonicalPositions = Dictionary(
            uniqueKeysWithValues: tracks.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )

        return tracks.sorted { lhs, rhs in
            let order = comparison(
                lhs,
                rhs,
                field: descriptor.field
            )
            guard order != .orderedSame else {
                let lhsPosition = canonicalPositions[lhs.id] ?? .max
                let rhsPosition = canonicalPositions[rhs.id] ?? .max
                if lhsPosition != rhsPosition {
                    return lhsPosition < rhsPosition
                }
                return lhs.id < rhs.id
            }

            return descriptor.direction == .ascending
                ? order == .orderedAscending
                : order == .orderedDescending
        }
    }

    static func artworkLayout(
        for tracks: [TrackPreview]
    ) -> SmartCollectionArtworkLayout {
        var seenAlbumIDs: Set<AlbumPreview.ID> = []
        var slots: [SmartCollectionArtworkSlot] = []

        for track in tracks where seenAlbumIDs.insert(track.albumID).inserted {
            slots.append(
                SmartCollectionArtworkSlot(
                    albumID: track.albumID,
                    albumTitle: track.album,
                    palette: track.artworkPalette
                )
            )
            if slots.count == 4 {
                break
            }
        }

        let kind: SmartCollectionArtworkLayout.Kind = switch slots.count {
        case 0: .empty
        case 1: .single
        case 2: .split
        case 3: .trio
        default: .grid
        }
        return SmartCollectionArtworkLayout(kind: kind, slots: slots)
    }

    static func totalDuration(of tracks: [TrackPreview]) -> TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    private static func comparison(
        _ lhs: TrackPreview,
        _ rhs: TrackPreview,
        field: SmartCollectionSortField
    ) -> ComparisonResult {
        switch field {
        case .canonical:
            .orderedSame
        case .title:
            compare(lhs.title, rhs.title)
        case .artist:
            compare(lhs.artist, rhs.artist)
        case .album:
            compare(lhs.album, rhs.album)
        case .year:
            compare(lhs.year, rhs.year)
        case .format:
            compare(lhs.format, rhs.format)
        case .duration:
            compare(lhs.duration, rhs.duration)
        }
    }

    private static func compare(
        _ lhs: String,
        _ rhs: String
    ) -> ComparisonResult {
        let locale = Locale(identifier: "en_US_POSIX")
        let options: String.CompareOptions = [
            .caseInsensitive,
            .diacriticInsensitive,
            .widthInsensitive,
        ]
        let normalizedLHS = lhs.folding(options: options, locale: locale)
        let normalizedRHS = rhs.folding(options: options, locale: locale)
        return normalizedLHS.compare(
            normalizedRHS,
            options: .literal,
            locale: locale
        )
    }

    private static func compare<T: Comparable>(
        _ lhs: T,
        _ rhs: T
    ) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }
}
