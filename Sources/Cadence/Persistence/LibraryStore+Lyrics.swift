import Foundation

extension LibraryStore {
    func lyricsDocument(
        trackID: UUID
    ) async throws -> LyricDocument? {
        guard let lyricsService else {
            return nil
        }
        return try await lyricsService.load(trackID: trackID)
    }

    func saveLyrics(
        _ document: LyricDocument
    ) async throws {
        guard let lyricsService else {
            throw ManagedLyricsServiceError.unavailable
        }
        try await lyricsService.save(document)
    }

    func recoverLyricsEdits() async throws -> ManagedLyricsRecoveryResult {
        guard let lyricsService else {
            return .empty
        }
        return try await lyricsService.recover()
    }
}
