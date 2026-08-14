import Foundation

extension CadenceAppModel {
    var isArtistSearchActive: Bool {
        !artistSearchQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    var shouldPresentArtistSearchResults: Bool {
        guard case .detail = artistsPresentation else {
            return isArtistSearchActive
        }
        return false
    }

    var presentedArtist: ArtistPreview? {
        guard case let .detail(artistID, _) = artistsPresentation else {
            return nil
        }
        return artists.first { $0.id == artistID }
    }

    func tracksForArtist(
        _ artistID: ArtistPreview.ID
    ) -> [TrackPreview] {
        tracks.filter { $0.artistID == artistID }
    }

    func albumsForArtist(
        _ artistID: ArtistPreview.ID
    ) -> [AlbumPreview] {
        albums.filter { $0.artist == artistID }
    }

    func canonicalTracks(
        for artist: ArtistPreview
    ) -> [TrackPreview] {
        ArtistListeningProjection.canonicalTracks(
            tracksForArtist(artist.id)
        )
    }

    func derivedTags(
        for artist: ArtistPreview,
        limit: Int = 5
    ) -> [TagPreview] {
        var counts: [TagPreview.ID: Int] = [:]
        for track in tracksForArtist(artist.id) {
            for tag in effectiveTags(for: track) {
                counts[tag.id, default: 0] += 1
            }
        }

        return Array(
            tags
                .filter { counts[$0.id] != nil }
                .sorted { lhs, rhs in
                    let lhsCount = counts[lhs.id, default: 0]
                    let rhsCount = counts[rhs.id, default: 0]
                    if lhsCount != rhsCount {
                        return lhsCount > rhsCount
                    }
                    return lhs.displayPath.localizedStandardCompare(
                        rhs.displayPath
                    ) == .orderedAscending
                }
                .prefix(max(limit, 0))
        )
    }

    func isFavorite(_ artist: ArtistPreview) -> Bool {
        favoriteArtistDates[artist.id] != nil
    }

    func setArtistFavorite(
        _ artist: ArtistPreview,
        isFavorite: Bool,
        at date: Date = .now
    ) {
        guard artists.contains(where: { $0.id == artist.id }) else {
            return
        }
        if isFavorite {
            if favoriteArtistDates[artist.id] == nil {
                favoriteArtistDates[artist.id] = date
            }
        } else {
            favoriteArtistDates.removeValue(forKey: artist.id)
        }
    }

    func toggleFavorite(
        _ artist: ArtistPreview,
        at date: Date = .now
    ) {
        setArtistFavorite(
            artist,
            isFavorite: !isFavorite(artist),
            at: date
        )
    }

    func activateAllArtistsSort(_ field: ArtistSortField) {
        if allArtistsSortDescriptor.field == field {
            allArtistsSortDescriptor = ArtistSortDescriptor(
                field: field,
                direction: allArtistsSortDescriptor.direction == .ascending
                    ? .descending
                    : .ascending
            )
        } else {
            allArtistsSortDescriptor = .defaultDescriptor(for: field)
        }
    }

    func requestOpenArtist(
        _ artist: ArtistPreview,
        origin: ArtistsBrowseOrigin
    ) {
        guard artists.contains(where: { $0.id == artist.id }) else {
            return
        }
        selectArtist(artist)
        selectedTrackID = canonicalTracks(for: artist).first?.id
        artistsFocusedArtistID = artist.id
        artistsPresentation = .detail(artist.id, origin: origin)
    }

    func requestArtistsBack() {
        if hasContextualBackNavigation {
            requestContextualBack()
            return
        }
        guard case let .detail(_, origin) = artistsPresentation else {
            artistsPresentation = .overview
            return
        }
        artistsPresentation = switch origin {
        case .overview, .search:
            .overview
        case let .shelf(kind):
            .shelf(kind)
        }
    }

    func prepareArtistsDestination() {
        guard case let .detail(artistID, _) = artistsPresentation else {
            return
        }
        guard artists.contains(where: { $0.id == artistID }) else {
            artistsPresentation = .overview
            return
        }
    }
}
