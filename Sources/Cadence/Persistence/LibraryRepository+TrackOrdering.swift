import Foundation
import SwiftData

extension LibraryRepository {
    func albumTracksInPlaybackOrder(
        albumID: UUID
    ) throws -> [LibraryTrackProjection] {
        let predicate = #Predicate<TrackRecord> {
            $0.album?.id == albumID
        }
        let records = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
        .sorted(by: Self.albumTrackOrder)
        return try trackProjections(records)
    }

    static func albumTrackOrder(
        lhs: TrackRecord,
        rhs: TrackRecord
    ) -> Bool {
        let lhsDisc = lhs.discNumber ?? 1
        let rhsDisc = rhs.discNumber ?? 1
        if lhsDisc != rhsDisc {
            return lhsDisc < rhsDisc
        }
        let lhsTrack = lhs.trackNumber ?? .max
        let rhsTrack = rhs.trackNumber ?? .max
        if lhsTrack != rhsTrack {
            return lhsTrack < rhsTrack
        }
        if lhs.normalizedTitle != rhs.normalizedTitle {
            return lhs.normalizedTitle < rhs.normalizedTitle
        }
        return lhs.sortIdentity < rhs.sortIdentity
    }

    static func artistTrackOrder(
        lhs: TrackRecord,
        rhs: TrackRecord
    ) -> Bool {
        let lhsAlbum = lhs.album?.normalizedTitle ?? ""
        let rhsAlbum = rhs.album?.normalizedTitle ?? ""
        if lhsAlbum != rhsAlbum {
            return lhsAlbum < rhsAlbum
        }
        return albumTrackOrder(lhs: lhs, rhs: rhs)
    }

    static func relationshipTrackOrder(
        lhs: TrackRecord,
        rhs: TrackRecord,
        sort: LibraryTrackSort
    ) -> Bool {
        let primaryOrder: Bool? = switch sort.field {
        case .album:
            optionalSortOrder(
                lhs.album?.normalizedTitle,
                rhs.album?.normalizedTitle,
                direction: sort.direction
            )
        case .year:
            optionalSortOrder(
                lhs.album?.year,
                rhs.album?.year,
                direction: sort.direction
            )
        case .song, .duration:
            nil
        }
        return primaryOrder ?? (lhs.sortIdentity < rhs.sortIdentity)
    }

    private static func optionalSortOrder<Value: Comparable>(
        _ lhs: Value?,
        _ rhs: Value?,
        direction: LibraryTrackSortDirection
    ) -> Bool? {
        switch (lhs, rhs) {
        case (nil, nil):
            nil
        case (nil, .some):
            direction == .ascending
        case (.some, nil):
            direction == .descending
        case let (lhs?, rhs?) where lhs != rhs:
            direction == .ascending ? lhs < rhs : lhs > rhs
        default:
            nil
        }
    }
}
