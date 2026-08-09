import Foundation

enum ReleaseKind: String, Codable, CaseIterable, Hashable, Sendable {
    case single
    case ep
    case album

    static func classify(
        metadata: String?,
        trackCount: Int,
        duration: TimeInterval
    ) -> Self {
        if let explicit = metadata.flatMap(normalizedMetadata) {
            return explicit
        }

        let count = max(trackCount, 0)
        let boundedDuration = max(duration, 0)
        guard count > 0, boundedDuration <= 30 * 60 else {
            return .album
        }
        if count <= 3 {
            return .single
        }
        if count <= 6 {
            return .ep
        }
        return .album
    }

    static func classify(
        album: AlbumRecord
    ) -> Self {
        let orderedTracks = album.tracks.sorted {
            let lhsDisc = $0.discNumber ?? .max
            let rhsDisc = $1.discNumber ?? .max
            if lhsDisc != rhsDisc {
                return lhsDisc < rhsDisc
            }
            let lhsTrack = $0.trackNumber ?? .max
            let rhsTrack = $1.trackNumber ?? .max
            if lhsTrack != rhsTrack {
                return lhsTrack < rhsTrack
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        let metadata = orderedTracks.lazy.compactMap {
            explicitMetadata(in: $0.sourceMetadata)
        }.first
        let trackCount = max(album.trackCount, orderedTracks.count)
        let trackDuration = orderedTracks.reduce(0) { $0 + $1.duration }
        let duration = max(album.totalDuration, trackDuration)
        return classify(
            metadata: metadata,
            trackCount: trackCount,
            duration: duration
        )
    }
}

private extension ReleaseKind {
    static let releaseTypeKeys: Set<String> = [
        "albumtype",
        "musicbrainzalbumtype",
        "musicbrainzreleasetype",
        "releasetype",
        "releasetypeprimary",
    ]

    static func normalizedMetadata(
        _ value: String
    ) -> Self? {
        let normalized = value.lowercased().filter(\.isLetter)
        return switch normalized {
        case "single": .single
        case "ep", "extendedplay": .ep
        case "album", "lp", "compilation": .album
        default: nil
        }
    }

    static func explicitMetadata(
        in data: Data?
    ) -> String? {
        guard
            let data,
            let snapshot = try? JSONDecoder().decode(
                SourceMetadataSnapshot.self,
                from: data
            )
        else {
            return nil
        }
        for item in snapshot.items {
            let keys = [
                item.rawKey,
                item.canonicalKey,
                item.identifier ?? "",
            ]
            let matchesReleaseType = keys.contains { key in
                releaseTypeKeys.contains(
                    key.lowercased().filter(\.isLetter)
                )
            }
            if matchesReleaseType,
               let value = item.stringValue,
               normalizedMetadata(value) != nil {
                return value
            }
        }
        return nil
    }
}
