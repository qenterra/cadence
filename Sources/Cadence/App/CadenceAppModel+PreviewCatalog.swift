import Foundation

extension CadenceAppModel {
    var artists: [ArtistPreview] {
        Dictionary(grouping: tracks, by: \.artistID)
            .map { artistID, artistTracks in
                ArtistPreview(
                    id: artistID,
                    name: artistTracks.first?.artist ?? artistID,
                    albumCount: Set(artistTracks.map(\.albumID)).count,
                    trackCount: artistTracks.count
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selectedArtist: ArtistPreview? {
        artists.first { $0.id == selectedArtistID }
    }

    var albums: [AlbumPreview] {
        Dictionary(grouping: tracks, by: \.albumID)
            .map { albumID, albumTracks in
                let firstTrack = albumTracks.first
                let genres = Set(
                    albumTracks.flatMap { track in
                        effectiveTags(for: track)
                            .filter { $0.groupID == .hierarchy("genre") }
                            .map(\.displayName)
                    }
                )
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

                return AlbumPreview(
                    id: albumID,
                    title: firstTrack?.album ?? albumID,
                    artist: firstTrack?.artist ?? "Unknown Artist",
                    year: firstTrack?.year ?? 0,
                    trackCount: albumTracks.count,
                    totalDuration: albumTracks.reduce(0) { $0 + $1.duration },
                    artworkPalette: albumTracks.compactMap(\.artworkPalette).first,
                    genres: Array(genres.prefix(2))
                )
            }
            .sorted(by: albumComesBefore)
    }

    var albumsForSelectedArtist: [AlbumPreview] {
        guard let selectedArtistID else {
            return []
        }
        return albums(for: selectedArtistID)
    }

    var selectedAlbum: AlbumPreview? {
        albumsForSelectedArtist.first { $0.id == selectedAlbumID }
    }

    var selectedAlbumTracks: [TrackPreview] {
        AlbumListeningProjection.canonicalTracks(
            tracks.filter { $0.albumID == selectedAlbumID }
        )
    }

    var visibleTracks: [TrackPreview] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return selectedAlbumTracks
        }

        let source = searchScope == .library ? tracks : selectedAlbumTracks
        return source.filter { track in
            track.title.localizedStandardContains(query)
                || track.artist.localizedStandardContains(query)
                || track.album.localizedStandardContains(query)
                || effectiveTags(for: track).contains {
                    $0.id.localizedStandardContains(query)
                }
        }
    }

    var selectedTrack: TrackPreview? {
        tracks.first { $0.id == selectedTrackID }
    }

    var currentTrack: TrackPreview? {
        tracks.first { $0.id == currentTrackID }
    }

    func selectArtist(_ artist: ArtistPreview) {
        selectedArtistID = artist.id
        let firstAlbum = albums(for: artist.id).first
        selectedAlbumID = firstAlbum?.id
        selectedTrackID = tracks.first { $0.albumID == firstAlbum?.id }?.id
    }

    func selectAlbum(_ album: AlbumPreview) {
        selectedArtistID = album.artist
        selectedAlbumID = album.id
        selectedTrackID = tracks.first { $0.albumID == album.id }?.id
    }

    func selectTrack(_ track: TrackPreview) {
        selectedArtistID = track.artistID
        selectedAlbumID = track.albumID
        selectedTrackID = track.id
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    private func albums(for artistID: ArtistPreview.ID) -> [AlbumPreview] {
        albums.filter { $0.artist == artistID }
    }

    private func albumComesBefore(
        _ lhs: AlbumPreview,
        _ rhs: AlbumPreview
    ) -> Bool {
        let artistOrder = lhs.artist.localizedStandardCompare(rhs.artist)
        if artistOrder != .orderedSame {
            return artistOrder == .orderedAscending
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
