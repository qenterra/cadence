import AppKit
@testable import Cadence
import MediaPlayer
import Testing

@MainActor
struct SystemMediaArtworkProviderTests {
    @Test("Encoded artwork source resizes without crossing an NSImage")
    func encodedSourceResizesOffMainActor() async throws {
        let data = try imageData(
            size: NSSize(width: 32, height: 24)
        )
        let source = try #require(
            SystemMediaArtworkImageSource(data: data)
        )

        #expect(source.boundsSize == NSSize(width: 32, height: 24))

        let requestedSize = await Task.detached {
            source.image(
                at: NSSize(width: 16, height: 12)
            )?.size
        }.value

        #expect(requestedSize == NSSize(width: 16, height: 12))
    }

    @Test("Invalid encoded artwork never creates a media image source")
    func invalidEncodedSource() {
        #expect(
            SystemMediaArtworkImageSource(data: Data([0x00, 0x01])) == nil
        )
    }

    @Test("System artwork can be requested from MediaPlayer's private queue")
    func servesArtworkOutsideMainActor() async throws {
        let artworkID = UUID()
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        let data = try #require(image.tiffRepresentation)
        let provider = SystemMediaArtworkProvider { requestedID in
            #expect(requestedID == artworkID)
            return ArtworkAsset(id: artworkID, data: data)
        }

        let artwork = try #require(await provider.artwork(for: artworkID))
        let sendableArtwork = SendableMediaItemArtwork(artwork)
        let requestedImage = await Task.detached {
            sendableArtwork.value.image(
                at: NSSize(width: 16, height: 16)
            )
        }.value

        #expect(requestedImage != nil)
        #expect(requestedImage?.size == NSSize(width: 16, height: 16))
    }

    @Test("System Now Playing publishes the current track artwork")
    func publishesCurrentArtwork() async {
        let artworkID = UUID()
        let artwork = MPMediaItemArtwork(
            boundsSize: NSSize(width: 32, height: 32)
        ) { _ in
            NSImage(size: NSSize(width: 32, height: 32))
        }
        let center = NowPlayingInfoPublisherStub()
        let provider = ImmediateSystemArtworkProvider(
            artworks: [artworkID: artwork]
        )
        let session = SystemMediaSession(
            nowPlayingInfoCenter: center,
            artworkProvider: provider
        )

        session.update(state: state(artworkID: artworkID))
        await waitForArtwork(in: center)

        #expect(
            center.nowPlayingInfo?[MPMediaItemPropertyArtwork]
                as? MPMediaItemArtwork === artwork
        )
    }

    @Test("A delayed previous artwork cannot replace the current track")
    func rejectsStaleArtwork() async {
        let firstArtworkID = UUID()
        let secondArtworkID = UUID()
        let firstArtwork = testArtwork(size: 24)
        let secondArtwork = testArtwork(size: 48)
        let center = NowPlayingInfoPublisherStub()
        let provider = DelayedSystemArtworkProvider(
            artworks: [
                firstArtworkID: firstArtwork,
                secondArtworkID: secondArtwork,
            ],
            delays: [
                firstArtworkID: .milliseconds(50),
                secondArtworkID: .milliseconds(10),
            ]
        )
        let session = SystemMediaSession(
            nowPlayingInfoCenter: center,
            artworkProvider: provider
        )

        session.update(state: state(artworkID: firstArtworkID))
        await Task.yield()
        session.update(state: state(artworkID: secondArtworkID))
        await Task.yield()

        await waitForArtwork(in: center)
        #expect(
            center.nowPlayingInfo?[MPMediaItemPropertyArtwork]
                as? MPMediaItemArtwork === secondArtwork
        )
    }

    @Test("Same-track artwork replacement bypasses the Now Playing throttle")
    func sameTrackArtworkReplacementPublishesImmediately() async {
        let trackID = UUID()
        let firstArtworkID = UUID()
        let secondArtworkID = UUID()
        let firstArtwork = testArtwork(size: 24)
        let secondArtwork = testArtwork(size: 48)
        let center = NowPlayingInfoPublisherStub()
        let provider = ImmediateSystemArtworkProvider(
            artworks: [
                firstArtworkID: firstArtwork,
                secondArtworkID: secondArtwork,
            ]
        )
        let session = SystemMediaSession(
            nowPlayingInfoCenter: center,
            artworkProvider: provider
        )

        session.update(state: state(trackID: trackID, artworkID: firstArtworkID))
        await waitForArtwork(firstArtwork, in: center)
        session.update(state: state(trackID: trackID, artworkID: secondArtworkID))
        await waitForArtwork(secondArtwork, in: center)

        #expect(
            center.nowPlayingInfo?[MPMediaItemPropertyArtwork]
                as? MPMediaItemArtwork === secondArtwork
        )
    }

    @Test("Same-track artwork removal clears Now Playing without waiting")
    func sameTrackArtworkRemovalPublishesImmediately() async {
        let trackID = UUID()
        let artworkID = UUID()
        let artwork = testArtwork(size: 32)
        let center = NowPlayingInfoPublisherStub()
        let provider = ImmediateSystemArtworkProvider(
            artworks: [artworkID: artwork]
        )
        let session = SystemMediaSession(
            nowPlayingInfoCenter: center,
            artworkProvider: provider
        )

        session.update(state: state(trackID: trackID, artworkID: artworkID))
        await waitForArtwork(artwork, in: center)
        session.update(state: state(trackID: trackID, artworkID: nil))

        #expect(center.nowPlayingInfo?[MPMediaItemPropertyArtwork] == nil)
    }

    private func state(
        trackID: UUID = UUID(),
        artworkID: UUID?
    ) -> PlaybackCoordinatorState {
        let resolved = playbackTestTrack(
            id: trackID,
            title: "Track",
            artworkID: artworkID
        )
        return PlaybackCoordinatorState(
            transport: .playing,
            currentTrack: resolved.track,
            duration: resolved.track.duration
        )
    }

    private func testArtwork(
        size: CGFloat
    ) -> MPMediaItemArtwork {
        MPMediaItemArtwork(
            boundsSize: NSSize(width: size, height: size)
        ) { _ in
            NSImage(size: NSSize(width: size, height: size))
        }
    }

    private func imageData(size: NSSize) throws -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return try #require(image.tiffRepresentation)
    }

    private func waitForArtwork(
        in center: NowPlayingInfoPublisherStub
    ) async {
        for _ in 0 ..< 100 {
            if center.nowPlayingInfo?[MPMediaItemPropertyArtwork] != nil {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func waitForArtwork(
        _ expected: MPMediaItemArtwork,
        in center: NowPlayingInfoPublisherStub
    ) async {
        for _ in 0 ..< 100 {
            if center.nowPlayingInfo?[MPMediaItemPropertyArtwork]
                as? MPMediaItemArtwork === expected {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

private struct SendableMediaItemArtwork: @unchecked Sendable {
    let value: MPMediaItemArtwork

    init(_ value: MPMediaItemArtwork) {
        self.value = value
    }
}

@MainActor
private final class NowPlayingInfoPublisherStub: NowPlayingInfoPublishing {
    var nowPlayingInfo: [String: Any]?
    var playbackState: MPNowPlayingPlaybackState = .stopped
}

@MainActor
private final class ImmediateSystemArtworkProvider: SystemMediaArtworkProviding {
    let artworks: [UUID: MPMediaItemArtwork]

    init(artworks: [UUID: MPMediaItemArtwork]) {
        self.artworks = artworks
    }

    func artwork(for id: UUID) async -> MPMediaItemArtwork? {
        artworks[id]
    }
}

@MainActor
private final class DelayedSystemArtworkProvider: SystemMediaArtworkProviding {
    let artworks: [UUID: MPMediaItemArtwork]
    let delays: [UUID: Duration]

    init(
        artworks: [UUID: MPMediaItemArtwork],
        delays: [UUID: Duration]
    ) {
        self.artworks = artworks
        self.delays = delays
    }

    func artwork(for id: UUID) async -> MPMediaItemArtwork? {
        if let delay = delays[id] {
            try? await Task.sleep(for: delay)
        }
        return artworks[id]
    }
}
