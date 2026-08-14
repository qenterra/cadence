import Foundation

enum LibraryProjectionFactory {
    static func track(
        _ track: TrackRecord,
        creditedArtistNames: [String] = []
    ) -> LibraryTrackProjection {
        let artistNames = creditedArtistNames.isEmpty
            ? [track.artist?.name ?? "Unknown Artist"]
            : creditedArtistNames
        return LibraryTrackProjection(
            id: track.id,
            title: track.title,
            artistID: track.artist?.id,
            artist: artistNames.joined(separator: ", "),
            albumID: track.album?.id,
            album: track.album?.title ?? "Unknown Album",
            duration: track.duration,
            year: track.album?.year,
            codec: track.codec,
            sampleRate: track.sampleRate,
            channelCount: track.channelCount,
            bitDepth: track.bitDepth,
            isFavorite: track.isFavorite,
            isExplicit: TrackContentRating.isExplicit(
                sourceMetadata: track.sourceMetadata
            ),
            customArtworkID: track.customArtworkID,
            artworkID:
            track.customArtworkID ?? track.album?.customArtworkID,
            relativeMediaPath: track.relativeMediaPath,
            lastPlayedAt: track.lastPlayedAt,
            hasSynchronizedLyrics: track.lyrics?.parsingStatus == .valid
                && track.lyrics?.timingStatus == .synchronized
        )
    }

    static func artist(
        _ artist: ArtistRecord,
        albumCount: Int? = nil
    ) -> LibraryArtistProjection {
        LibraryArtistProjection(
            id: artist.id,
            name: artist.name,
            albumCount: albumCount ?? artist.albumCount,
            trackCount: artist.trackCount,
            isFavorite: artist.isFavorite,
            favoriteDate: artist.favoriteDate,
            customArtworkID: artist.customArtworkID
        )
    }

    static func album(
        _ album: AlbumRecord,
        creditedArtistNames: [String] = []
    ) -> LibraryAlbumProjection {
        let artistNames = creditedArtistNames.isEmpty
            ? [album.artist?.name ?? "Unknown Artist"]
            : creditedArtistNames
        return LibraryAlbumProjection(
            id: album.id,
            title: album.title,
            artistID: album.artist?.id,
            artist: artistNames.joined(separator: ", "),
            year: album.year,
            trackCount: album.trackCount,
            totalDuration: album.totalDuration,
            isFavorite: album.isFavorite,
            favoriteDate: album.favoriteDate,
            customArtworkID: album.customArtworkID,
            releaseKind: ReleaseKind.classify(album: album)
        )
    }

    static func tag(
        _ tag: TagRecord
    ) -> LibraryTagProjection {
        LibraryTagProjection(
            id: tag.id,
            displayPath: tag.displayPath,
            groupPath: tag.groupPath
        )
    }

    static func playback(
        _ track: TrackRecord,
        creditedArtistNames: [String] = []
    ) -> PlaybackTrack {
        let artistNames = creditedArtistNames.isEmpty
            ? [track.artist?.name ?? "Unknown Artist"]
            : creditedArtistNames
        return PlaybackTrack(
            id: track.id,
            title: track.title,
            artistID: track.artist?.id,
            artist: artistNames.joined(separator: ", "),
            albumID: track.album?.id,
            album: track.album?.title ?? "Unknown Album",
            duration: track.duration,
            codec: track.codec,
            container: track.container,
            sampleRate: track.sampleRate,
            channelCount: track.channelCount,
            bitrate: track.bitrate,
            bitDepth: track.bitDepth,
            spatialFormat: track.spatialFormat,
            relativeMediaPath: track.relativeMediaPath,
            lyricRelativePath: track.lyrics?.relativePath,
            artworkID: track.customArtworkID ?? track.album?.customArtworkID,
            replayGainTrackGain: track.replayGainTrackGain,
            replayGainTrackPeak: track.replayGainTrackPeak,
            year: track.album?.year,
            discNumber: track.discNumber,
            trackNumber: track.trackNumber
        )
    }
}
