import Foundation

struct ExternalAudioItem: Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL
    let resolvedTrack: ResolvedPlaybackTrack
    let artwork: ArtworkAsset?
}

struct ExternalAudioOpenResult: Sendable {
    let items: [ExternalAudioItem]
    let skippedCount: Int
    let failures: [String]
}

@MainActor
protocol SecurityScopedResourceAccessing: AnyObject {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

@MainActor
final class URLSecurityScopeAccess: SecurityScopedResourceAccessing {
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

@MainActor
final class ExternalAudioSession {
    private let metadataReader: any AudioMetadataReading
    private let securityScope: any SecurityScopedResourceAccessing
    private var itemsByID: [UUID: ExternalAudioItem] = [:]
    private var pendingScopedURLs: [UUID: URL] = [:]
    private var activeScopedURLs: [UUID: URL] = [:]

    init(
        metadataReader: any AudioMetadataReading = MetadataReader(),
        securityScope: any SecurityScopedResourceAccessing = URLSecurityScopeAccess()
    ) {
        self.metadataReader = metadataReader
        self.securityScope = securityScope
    }

    func prepare(urls: [URL]) async -> ExternalAudioOpenResult {
        release(&pendingScopedURLs)
        var seen: Set<URL> = []
        let uniqueURLs = urls
            .map(\.standardizedFileURL)
            .filter { seen.insert($0).inserted }
        var items: [ExternalAudioItem] = []
        var skippedCount = 0
        var failures: [String] = []

        for url in uniqueURLs {
            guard isSupportedRegularFile(url) else {
                skippedCount += 1
                if SupportedAudioFormat(pathExtension: url.pathExtension) != nil {
                    failures.append("Cadence could not read \(url.lastPathComponent).")
                }
                continue
            }

            let acquiredScope = securityScope.startAccessing(url)
            do {
                let metadata = try await metadataReader.read(url: url)
                let artworkPayload = await metadataReader.readEmbeddedArtwork(
                    url: url
                )
                let item = makeItem(
                    url: url,
                    metadata: metadata,
                    artworkPayload: artworkPayload
                )
                items.append(item)
                if acquiredScope {
                    pendingScopedURLs[item.id] = url
                }
            } catch {
                if acquiredScope {
                    securityScope.stopAccessing(url)
                }
                skippedCount += 1
                failures.append(error.localizedDescription)
            }
        }

        return ExternalAudioOpenResult(
            items: items,
            skippedCount: skippedCount,
            failures: failures
        )
    }

    func replace(with items: [ExternalAudioItem]) {
        release(&activeScopedURLs)
        let retainedIDs = Set(items.map(\.id))
        var nextActive: [UUID: URL] = [:]
        for (id, url) in pendingScopedURLs {
            if retainedIDs.contains(id) {
                nextActive[id] = url
            } else {
                securityScope.stopAccessing(url)
            }
        }
        pendingScopedURLs = [:]
        activeScopedURLs = nextActive
        itemsByID = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0) }
        )
    }

    func resolvedTracks(ids: [UUID]) -> [ResolvedPlaybackTrack] {
        ids.compactMap { itemsByID[$0]?.resolvedTrack }
    }

    func item(id: UUID) -> ExternalAudioItem? {
        itemsByID[id]
    }

    func artwork(id: UUID) -> ArtworkAsset? {
        itemsByID.values.first { $0.artwork?.id == id }?.artwork
    }

    func end() {
        release(&pendingScopedURLs)
        release(&activeScopedURLs)
        itemsByID = [:]
    }

    private func isSupportedRegularFile(_ url: URL) -> Bool {
        guard SupportedAudioFormat(pathExtension: url.pathExtension) != nil,
              let values = try? url.resourceValues(
                  forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              )
        else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func makeItem(
        url: URL,
        metadata: ScannedAudioMetadata,
        artworkPayload: EmbeddedArtworkPayload?
    ) -> ExternalAudioItem {
        let id = UUID()
        let artwork = artworkPayload.flatMap { payload in
            payload.data.isEmpty ? nil : ArtworkAsset(data: payload.data)
        }
        let track = PlaybackTrack(
            id: id,
            title: metadata.title,
            artistID: nil,
            artist: metadata.artist,
            albumID: nil,
            album: metadata.album,
            duration: metadata.duration,
            codec: metadata.codec,
            container: metadata.container,
            sampleRate: metadata.sampleRate,
            channelCount: metadata.channelCount,
            bitrate: metadata.bitrate,
            bitDepth: metadata.bitDepth,
            spatialFormat: metadata.spatialFormat,
            relativeMediaPath: url.path,
            lyricRelativePath: nil,
            artworkID: artwork?.id,
            replayGainTrackGain: nil,
            replayGainTrackPeak: nil,
            year: metadata.year,
            discNumber: metadata.discNumber,
            trackNumber: metadata.trackNumber
        )
        return ExternalAudioItem(
            id: id,
            sourceURL: url,
            resolvedTrack: ResolvedPlaybackTrack(track: track, mediaURL: url),
            artwork: artwork
        )
    }

    private func release(_ scopedURLs: inout [UUID: URL]) {
        for url in scopedURLs.values {
            securityScope.stopAccessing(url)
        }
        scopedURLs = [:]
    }
}

extension ExternalAudioItem {
    var libraryProjection: LibraryTrackProjection {
        let track = resolvedTrack.track
        return LibraryTrackProjection(
            id: track.id,
            title: track.title,
            artistID: track.artistID,
            artist: track.artist,
            albumID: track.albumID,
            album: track.album,
            duration: track.duration,
            year: track.year,
            codec: track.codec,
            sampleRate: track.sampleRate,
            channelCount: track.channelCount,
            bitDepth: track.bitDepth,
            isFavorite: false,
            customArtworkID: nil,
            artworkID: track.artworkID,
            relativeMediaPath: track.relativeMediaPath,
            lastPlayedAt: nil,
            hasSynchronizedLyrics: false
        )
    }
}
