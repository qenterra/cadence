import Foundation
import QenTerraMediaComponents
import Testing

struct LyricsScrollPresentationTests {
    @Test("A new track resets before following later active lines")
    func trackResetAndFollow() {
        let trackA = UUID()
        let trackB = UUID()
        let firstLine = UUID()
        let secondLine = UUID()

        #expect(
            LyricsScrollDecision<UUID>.resolve(
                previousResetIdentity: Optional<UUID>.none,
                currentResetIdentity: trackA,
                previousIdentity: Optional<UUID>.none,
                currentIdentity: firstLine,
                reducesMotion: false
            ) == .top
        )
        #expect(
            LyricsScrollDecision<UUID>.resolve(
                previousResetIdentity: trackA,
                currentResetIdentity: trackA,
                previousIdentity: firstLine,
                currentIdentity: firstLine,
                reducesMotion: false
            ) == .none
        )
        #expect(
            LyricsScrollDecision<UUID>.resolve(
                previousResetIdentity: trackA,
                currentResetIdentity: trackA,
                previousIdentity: firstLine,
                currentIdentity: secondLine,
                reducesMotion: false
            ) == .line(id: secondLine, duration: 0.32)
        )
        #expect(
            LyricsScrollDecision<UUID>.resolve(
                previousResetIdentity: trackA,
                currentResetIdentity: trackB,
                previousIdentity: secondLine,
                currentIdentity: secondLine,
                reducesMotion: false
            ) == .top
        )
    }

    @Test("Reduce Motion follows immediately without losing seeking")
    func reduceMotionFollow() {
        let firstLine = UUID()
        let secondLine = UUID()

        #expect(
            LyricsScrollDecision<UUID>.resolve(
                previousIdentity: firstLine,
                currentIdentity: secondLine,
                reducesMotion: true
            ) == .line(id: secondLine, duration: 0)
        )
    }
}
