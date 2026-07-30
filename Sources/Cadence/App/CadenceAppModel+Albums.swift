import Foundation

extension CadenceAppModel {
    var recentlyAddedAlbums: [AlbumPreview] {
        AlbumListeningProjection.sortedAlbums(
            albums,
            by: .recentlyAdded
        )
    }

    var favoriteAlbums: [AlbumPreview] {
        AlbumListeningProjection.sortedAlbums(
            albums.filter { favoriteAlbumDates[$0.id] != nil },
            by: .recentlyFavorited,
            favoriteDates: favoriteAlbumDates
        )
    }

    var sortedAllAlbums: [AlbumPreview] {
        AlbumListeningProjection.sortedAlbums(
            albums,
            by: allAlbumsSortDescriptor,
            favoriteDates: favoriteAlbumDates
        )
    }

    var visibleAlbumSearchResults: [AlbumPreview] {
        sortedAllAlbums.filter { album in
            AlbumListeningProjection.matchesSearch(
                album: album,
                query: albumSearchQuery,
                assignedTags: assignedTags(for: album)
            )
        }
    }

    var isAlbumSearchActive: Bool {
        !albumSearchQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    var shouldPresentAlbumSearchResults: Bool {
        guard case .detail = albumsPresentation else {
            return isAlbumSearchActive
        }
        return false
    }

    var presentedAlbum: AlbumPreview? {
        guard case let .detail(albumID, _) = albumsPresentation else {
            return nil
        }
        return albums.first { $0.id == albumID }
    }

    var albumsBackTitle: String {
        guard case let .detail(_, origin) = albumsPresentation else {
            return "Albums"
        }
        switch origin {
        case .overview, .search:
            return "Albums"
        case let .shelf(kind):
            return kind.title
        case let .artist(artistID):
            return artists.first { $0.id == artistID }?.name ?? "Artists"
        }
    }

    func albumShelfProjection(
        kind: AlbumShelfKind,
        capacity: Int
    ) -> AlbumShelfProjection {
        let source = switch kind {
        case .recentlyAdded:
            recentlyAddedAlbums
        case .favorites:
            favoriteAlbums
        }
        return AlbumListeningProjection.shelf(source, capacity: capacity)
    }

    func isFavorite(_ album: AlbumPreview) -> Bool {
        favoriteAlbumDates[album.id] != nil
    }

    func setAlbumFavorite(
        _ album: AlbumPreview,
        isFavorite: Bool,
        at date: Date = .now
    ) {
        guard albums.contains(where: { $0.id == album.id }) else {
            return
        }
        if isFavorite {
            if favoriteAlbumDates[album.id] == nil {
                favoriteAlbumDates[album.id] = date
            }
        } else {
            favoriteAlbumDates.removeValue(forKey: album.id)
        }
    }

    func toggleFavorite(
        _ album: AlbumPreview,
        at date: Date = .now
    ) {
        setAlbumFavorite(
            album,
            isFavorite: !isFavorite(album),
            at: date
        )
    }

    func activateAllAlbumsSort(_ field: AlbumSortField) {
        if allAlbumsSortDescriptor.field == field {
            allAlbumsSortDescriptor = AlbumSortDescriptor(
                field: field,
                direction: allAlbumsSortDescriptor.direction == .ascending
                    ? .descending
                    : .ascending
            )
        } else {
            allAlbumsSortDescriptor = .defaultDescriptor(for: field)
        }
    }

    func requestOpenAlbum(
        _ album: AlbumPreview,
        origin: AlbumsBrowseOrigin
    ) {
        guard albums.contains(where: { $0.id == album.id }) else {
            return
        }
        selectAlbum(album)
        selectedTrackID = AlbumListeningProjection.canonicalTracks(
            tracks.filter { $0.albumID == album.id }
        ).first?.id
        albumsFocusedAlbumID = album.id
        albumsPresentation = .detail(album.id, origin: origin)
        selectedDestination = .albums
    }

    func requestShowAll(_ kind: AlbumShelfKind) {
        albumShelfSortDescriptors[kind] = switch kind {
        case .recentlyAdded:
            .recentlyAdded
        case .favorites:
            .recentlyFavorited
        }
        albumsPresentation = .shelf(kind)
    }

    func requestAlbumsBack() {
        if hasContextualBackNavigation {
            requestContextualBack()
            return
        }
        guard case let .detail(_, origin) = albumsPresentation else {
            albumsPresentation = .overview
            return
        }
        albumsPresentation = switch origin {
        case .overview, .search:
            .overview
        case let .shelf(kind):
            .shelf(kind)
        case .artist:
            .overview
        }
        if case let .artist(artistID) = origin {
            let preservesExistingOrigin: Bool = if case let .detail(presentedArtistID, _) = artistsPresentation {
                presentedArtistID == artistID
            } else {
                false
            }
            let artistExists = artists.contains { $0.id == artistID }

            if !preservesExistingOrigin, artistExists {
                artistsPresentation = .detail(
                    artistID,
                    origin: .overview
                )
            }
            selectedDestination = .artists
        }
    }

    func updateAlbumsScrollAnchor(
        _ anchor: AlbumBrowseAnchor?,
        scope: AlbumShelfKind?
    ) {
        if let scope {
            albumGridScrollAnchors[scope] = anchor
        } else {
            albumsOverviewScrollAnchor = anchor
        }
    }

    func updateAlbumsFocus(_ albumID: AlbumPreview.ID?) {
        albumsFocusedAlbumID = albumID
    }

    func prepareAlbumsDestination() {
        guard case let .detail(albumID, _) = albumsPresentation else {
            return
        }
        guard albums.contains(where: { $0.id == albumID }) else {
            albumsPresentation = .overview
            return
        }
    }
}
