import Foundation

extension CadenceAppModel {
    @discardableResult
    func saveLyricDraft() -> Bool {
        guard
            var draft = lyricDraft,
            lyricDraftValidationIssues.isEmpty,
            case let .preview(trackID) = draft.trackID
        else {
            return false
        }

        if draft.document.timingStatus == .missing {
            lyricDocuments.removeValue(forKey: trackID)
        } else {
            lyricDocuments[trackID] = draft.document
        }
        draft.markSaved()
        lyricDraft = draft
        return true
    }

    @discardableResult
    func saveLyricDraftPersisting() async -> Bool {
        guard
            let draft = lyricDraft,
            lyricDraftValidationIssues.isEmpty
        else {
            return false
        }
        switch draft.trackID {
        case .preview:
            return saveLyricDraft()
        case let .managed(trackID):
            guard
                currentPlaybackTrack?.id == trackID,
                !isSavingLyricDraft
            else {
                return false
            }
            return await persistManagedLyricDraft(draft)
        }
    }

    @discardableResult
    func resolvePendingLyricsTransitionPersisting(
        _ resolution: LyricsDraftResolution
    ) async -> Bool {
        guard let target = pendingLyricsTransition else {
            return false
        }
        switch resolution {
        case .cancel:
            pendingLyricsTransition = nil
            return true
        case .discard:
            pendingLyricsTransition = nil
            performLyricsTransition(target)
            return true
        case .save:
            guard await saveLyricDraftPersisting() else {
                return false
            }
            pendingLyricsTransition = nil
            performLyricsTransition(target)
            return true
        }
    }

    @discardableResult
    func resolvePendingLyricsTransition(
        _ resolution: LyricsDraftResolution
    ) -> Bool {
        guard let target = pendingLyricsTransition else {
            return false
        }
        switch resolution {
        case .cancel:
            pendingLyricsTransition = nil
            return true
        case .discard:
            pendingLyricsTransition = nil
            performLyricsTransition(target)
            return true
        case .save:
            guard saveLyricDraft() else {
                return false
            }
            pendingLyricsTransition = nil
            performLyricsTransition(target)
            return true
        }
    }

    func dismissLyricPersistenceError() {
        lyricPersistenceError = nil
    }

    func replaceLyricDraftForCurrentTrack() {
        guard
            playbackWorkspace == .lyricsEditor,
            let currentTrack
        else {
            return
        }
        lyricDraft = LyricDraft(
            trackID: currentTrack.id,
            document: lyricDocuments[currentTrack.id]
        )
    }

    func loadProductionLyricDraft(
        trackID: UUID,
        requestID: UUID
    ) async {
        defer {
            if lyricLoadRequestID == requestID {
                isLoadingLyricDraft = false
            }
        }
        do {
            let document = try await librarySession.store.lyricsDocument(
                trackID: trackID
            )
            guard
                lyricLoadRequestID == requestID,
                playbackWorkspace == .lyricsEditor,
                currentPlaybackTrack?.id == trackID
            else {
                return
            }
            lyricDraft = LyricDraft(
                trackID: trackID,
                document: document
            )
        } catch {
            guard
                lyricLoadRequestID == requestID,
                playbackWorkspace == .lyricsEditor
            else {
                return
            }
            lyricPersistenceError = error.localizedDescription
            lyricDraft = nil
        }
    }
}

private extension CadenceAppModel {
    func persistManagedLyricDraft(_ draft: LyricDraft) async -> Bool {
        isSavingLyricDraft = true
        lyricPersistenceError = nil
        defer {
            isSavingLyricDraft = false
        }
        do {
            try await librarySession.store.saveLyrics(draft.document)
            markLyricDraftSaved(ifUnchangedFrom: draft)
            lyricsRevision += 1
            return true
        } catch {
            lyricPersistenceError = error.localizedDescription
            return false
        }
    }

    func markLyricDraftSaved(ifUnchangedFrom savedDraft: LyricDraft) {
        guard
            var currentDraft = lyricDraft,
            currentDraft.trackID == savedDraft.trackID
        else {
            return
        }
        if currentDraft.lines == savedDraft.lines,
           currentDraft.metadataLines == savedDraft.metadataLines {
            currentDraft.markSaved()
            lyricDraft = currentDraft
        }
    }
}
