import AVFoundation
import Foundation

struct EmbeddedLyricsPayload: Codable, Equatable, Sendable {
    let text: String
    let timingStatus: LyricTimingStatus
}

struct EmbeddedLyricsReader: Sendable {
    private static let synchronizedKeys: Set<String> = [
        "SYLT",
        "SYNCEDLYRICS",
        "SYNCHRONIZEDLYRICS",
    ]
    private static let unsynchronizedKeys: Set<String> = [
        "LYRICS",
        "UNSYNCEDLYRICS",
        "UNSYNCHRONIZEDLYRICS",
        "USLT",
    ]

    func read(
        items: [AVMetadataItem]
    ) async -> EmbeddedLyricsPayload? {
        let resolver = MetadataValueResolver(items: items)
        let synchronized = await resolver.strings(
            rawKeys: Self.synchronizedKeys
        )
        let unsynchronized = await resolver.strings(
            rawKeys: Self.unsynchronizedKeys
        )
        let candidates = synchronized + unsynchronized

        for candidate in candidates {
            guard
                let document = try? LineLevelLRC.parse(
                    candidate,
                    trackID: 0
                ),
                let normalized = try? LineLevelLRC.generate(document)
            else {
                continue
            }
            return EmbeddedLyricsPayload(
                text: normalized,
                timingStatus: document.timingStatus
            )
        }
        return nil
    }
}
