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
    ) async throws -> EmbeddedLyricsPayload? {
        let resolver = MetadataValueResolver(items: items)
        let synchronized = try await resolver.strings(
            rawKeys: Self.synchronizedKeys
        )
        let unsynchronized = try await resolver.strings(
            rawKeys: Self.unsynchronizedKeys
        )
        let candidates = synchronized + unsynchronized

        for candidate in candidates {
            do {
                let document = try LineLevelLRC.parse(
                    candidate,
                    trackID: 0
                )
                let normalized = try LineLevelLRC.generate(document)
                return EmbeddedLyricsPayload(
                    text: normalized,
                    timingStatus: document.timingStatus
                )
            } catch {
                // A malformed optional tag must not hide a later valid lyrics
                // tag or make an otherwise playable audio file unimportable.
                continue
            }
        }
        return nil
    }
}
