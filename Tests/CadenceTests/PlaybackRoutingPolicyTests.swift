@testable import Cadence
import Foundation
import Testing

struct PlaybackRoutingPolicyTests {
    struct RoutingCase: Sendable {
        let codec: String
        let container: String
        let channels: Int
        let spatial: StoredSpatialFormat
        let transport: AudioTransportKind
        let expected: PlaybackBackendKind
    }

    @Test(
        "Routing preserves native spatial paths and uses PCM for stereo lossless",
        arguments: [
            RoutingCase(
                codec: "FLAC",
                container: "flac",
                channels: 2,
                spatial: .stereo,
                transport: .builtIn,
                expected: .pcm
            ),
            RoutingCase(
                codec: "ALAC",
                container: "m4a",
                channels: 2,
                spatial: .stereo,
                transport: .airPlay,
                expected: .native
            ),
            RoutingCase(
                codec: "EAC3",
                container: "m4a",
                channels: 6,
                spatial: .dolbyAtmos,
                transport: .builtIn,
                expected: .native
            ),
            RoutingCase(
                codec: "AAC",
                container: "m4a",
                channels: 2,
                spatial: .stereo,
                transport: .builtIn,
                expected: .native
            ),
        ]
    )
    func routing(_ testCase: RoutingCase) {
        let resolved = playbackTestTrack(
            id: UUID(),
            title: "Track",
            codec: testCase.codec,
            container: testCase.container,
            channelCount: testCase.channels,
            spatialFormat: testCase.spatial
        )
        let backend = PlaybackRoutingPolicy.backend(
            for: PlaybackRoutingRequest(
                track: resolved.track,
                route: AudioRouteSnapshot(
                    name: "Output",
                    transport: testCase.transport
                )
            )
        )

        #expect(backend == testCase.expected)
    }

    @Test("Stereo lossless stays on the direct PCM path")
    func stereoLossless() {
        let resolved = playbackTestTrack(
            id: UUID(),
            title: "Stereo"
        )
        let request = PlaybackRoutingRequest(
            track: resolved.track,
            route: .unknown
        )

        #expect(PlaybackRoutingPolicy.backend(for: request) == .pcm)
        #expect(resolved.track.spatialFormat == .stereo)
    }
}
