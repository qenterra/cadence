import AppKit
@testable import Cadence
import MediaPlayer
import Testing

@MainActor
struct SystemMediaArtworkProviderTests {
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

    private func state(
        artworkID: UUID
    ) -> PlaybackCoordinatorState {
        let resolved = playbackTestTrack(
            id: UUID(),
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
