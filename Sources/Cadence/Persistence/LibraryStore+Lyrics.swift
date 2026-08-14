import Foundation

extension LibraryStore {
    func lyricsDocument(
        trackID: UUID
    ) async throws -> LyricDocument? {
        guard let lyricsService else {
            throw ManagedLyricsServiceError.unavailable
        }
        let document = try await lyricsService.load(trackID: trackID)
        await synchronizeLyricsSearch(trackIDs: [trackID])
        return document
    }

    func saveLyrics(
        _ document: LyricDocument
    ) async throws {
        guard let lyricsService else {
            throw ManagedLyricsServiceError.unavailable
        }
        try await lyricsService.save(document)
        if case let .managed(trackID) = document.trackID {
            await synchronizeLyricsSearch(trackIDs: [trackID])
        }
    }

    func recoverLyricsEdits() async throws -> ManagedLyricsRecoveryResult {
        guard let lyricsService else {
            throw ManagedLyricsServiceError.unavailable
        }
        let result = try await lyricsService.recover()
        await synchronizeLyricsSearch()
        return result
    }
}
