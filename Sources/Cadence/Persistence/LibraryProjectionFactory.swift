enum LibraryProjectionFactory {
    static func track(
        _ track: TrackRecord
    ) -> LibraryTrackProjection {
        LibraryTrackProjection(
            id: track.id,
            title: track.title,
            artistID: track.artist?.id,
            artist: track.artist?.name ?? "Unknown Artist",
            albumID: track.album?.id,
            album: track.album?.title ?? "Unknown Album",
            duration: track.duration,
            year: track.album?.year,
            codec: track.codec,
            sampleRate: track.sampleRate,
            channelCount: track.channelCount,
            bitDepth: track.bitDepth,
            isFavorite: track.isFavorite,
            customArtworkID: track.customArtworkID,
            artworkID:
            track.customArtworkID ?? track.album?.customArtworkID,
            relativeMediaPath: track.relativeMediaPath,
            dateAdded: track.dateAdded,
            lastPlayedAt: track.lastPlayedAt,
            playCount: track.playCount
        )
    }

    static func artist(
        _ artist: ArtistRecord
    ) -> LibraryArtistProjection {
        LibraryArtistProjection(
            id: artist.id,
            name: artist.name,
            albumCount: artist.albumCount,
            trackCount: artist.trackCount,
            isFavorite: artist.isFavorite,
            favoriteDate: artist.favoriteDate,
            customArtworkID: artist.customArtworkID
        )
    }

    static func album(
        _ album: AlbumRecord
    ) -> LibraryAlbumProjection {
        LibraryAlbumProjection(
            id: album.id,
            title: album.title,
            artistID: album.artist?.id,
            artist: album.artist?.name ?? "Unknown Artist",
            year: album.year,
            dateAdded: album.dateAdded,
            trackCount: album.trackCount,
            totalDuration: album.totalDuration,
            isFavorite: album.isFavorite,
            favoriteDate: album.favoriteDate,
            customArtworkID: album.customArtworkID
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
        _ track: TrackRecord
    ) -> PlaybackTrack {
        PlaybackTrack(
            id: track.id,
            title: track.title,
            artistID: track.artist?.id,
            artist: track.artist?.name ?? "Unknown Artist",
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
