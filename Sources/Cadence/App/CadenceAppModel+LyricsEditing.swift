import Foundation

extension CadenceAppModel {
    var currentLyricDocument: LyricDocument? {
        guard let currentTrackID else {
            return nil
        }
        return lyricDocuments[currentTrackID]
    }

    var isLyricDraftDirty: Bool {
        lyricDraft?.isDirty == true
    }

    var lyricDraftValidationIssues: [LyricValidationIssue] {
        guard let draft = lyricDraft else {
            return []
        }
        let duration: TimeInterval
        switch draft.trackID {
        case let .preview(trackID):
            guard let track = tracks.first(where: { $0.id == trackID }) else {
                return []
            }
            duration = track.duration
        case let .managed(trackID):
            guard currentPlaybackTrack?.id == trackID else {
                return []
            }
            duration = playbackDuration
        }
        return draft.document.validationIssues(
            trackDuration: duration
        )
    }

    var canSaveLyricDraft: Bool {
        isLyricDraftDirty
            && lyricDraftValidationIssues.isEmpty
            && !isLoadingLyricDraft
            && !isSavingLyricDraft
    }

    @discardableResult
    func presentLyricsEditor() -> Bool {
        if let currentTrack {
            lyricLoadRequestID = nil
            isLoadingLyricDraft = false
            lyricDraft = LyricDraft(
                trackID: currentTrack.id,
                document: lyricDocuments[currentTrack.id]
            )
            pendingLyricsTransition = nil
            lyricPersistenceError = nil
            playbackWorkspace = .lyricsEditor
            return true
        }
        guard let playbackTrack = currentPlaybackTrack else {
            return false
        }
        lyricDraft = nil
        pendingLyricsTransition = nil
        lyricPersistenceError = nil
        isLoadingLyricDraft = true
        let requestID = UUID()
        lyricLoadRequestID = requestID
        playbackWorkspace = .lyricsEditor
        Task {
            await loadProductionLyricDraft(
                trackID: playbackTrack.id,
                requestID: requestID
            )
        }
        return true
    }

    func requestCloseLyricsEditor() {
        guard playbackWorkspace == .lyricsEditor else {
            return
        }
        if isLyricDraftDirty {
            pendingLyricsTransition = .closeEditor
        } else {
            performLyricsTransition(.closeEditor)
        }
    }

    func updateLyricText(
        lineID: LyricLine.ID,
        text: String,
        undoManager: UndoManager? = nil
    ) {
        updateLyricDraft(
            actionName: "Edit Lyric",
            undoManager: undoManager
        ) { draft in
            guard
                let index = draft.lines.firstIndex(where: {
                    $0.id == lineID
                }),
                draft.lines[index].text != text
            else {
                return false
            }
            draft.lines[index].text = text
            return true
        }
    }

    func updateLyricTimestamp(
        lineID: LyricLine.ID,
        startTime: TimeInterval?,
        undoManager: UndoManager? = nil
    ) {
        updateLyricDraft(
            actionName: "Edit Lyric Time",
            undoManager: undoManager
        ) { draft in
            guard
                let index = draft.lines.firstIndex(where: {
                    $0.id == lineID
                }),
                draft.lines[index].startTime != startTime
            else {
                return false
            }
            draft.lines[index].startTime = startTime
            return true
        }
    }

    func activateLyricLine(_ lineID: LyricLine.ID) {
        guard
            var draft = lyricDraft,
            draft.lines.contains(where: { $0.id == lineID })
        else {
            return
        }
        draft.activeLineID = lineID
        lyricDraft = draft
    }

    func addLyricLine(
        after lineID: LyricLine.ID? = nil,
        undoManager: UndoManager? = nil
    ) {
        updateLyricDraft(
            actionName: "Add Lyric Line",
            undoManager: undoManager
        ) { draft in
            let newLine = LyricLine(text: "")
            let insertionIndex = lineID.flatMap { id in
                draft.lines.firstIndex(where: { $0.id == id })
                    .map { $0 + 1 }
            } ?? draft.lines.endIndex
            draft.lines.insert(newLine, at: insertionIndex)
            draft.activeLineID = newLine.id
            return true
        }
    }

    func removeLyricLine(
        _ lineID: LyricLine.ID,
        undoManager: UndoManager? = nil
    ) {
        updateLyricDraft(
            actionName: "Delete Lyric Line",
            undoManager: undoManager
        ) { draft in
            guard
                let index = draft.lines.firstIndex(where: {
                    $0.id == lineID
                })
            else {
                return false
            }
            draft.lines.remove(at: index)
            if draft.lines.isEmpty {
                draft.lines = [LyricLine(text: "")]
            }
            let nextIndex = min(index, draft.lines.index(before: draft.lines.endIndex))
            draft.activeLineID = draft.lines[nextIndex].id
            return true
        }
    }

    func moveLyricLine(
        _ lineID: LyricLine.ID,
        by offset: Int,
        undoManager: UndoManager? = nil
    ) {
        updateLyricDraft(
            actionName: "Reorder Lyric Lines",
            undoManager: undoManager
        ) { draft in
            guard
                let sourceIndex = draft.lines.firstIndex(where: {
                    $0.id == lineID
                })
            else {
                return false
            }
            let destinationIndex = min(
                max(sourceIndex + offset, draft.lines.startIndex),
                draft.lines.index(before: draft.lines.endIndex)
            )
            guard sourceIndex != destinationIndex else {
                return false
            }
            let line = draft.lines.remove(at: sourceIndex)
            draft.lines.insert(line, at: destinationIndex)
            return true
        }
    }

    func replaceLyricDraftWithPlainText(
        _ source: String,
        undoManager: UndoManager? = nil
    ) {
        let lines = LyricDocument.lines(fromPlainText: source)
        guard !lines.isEmpty else {
            return
        }
        replaceLyricDraftLines(
            lines,
            actionName: "Paste Lyrics",
            undoManager: undoManager
        )
    }

    @discardableResult
    func replaceLyricDraftWithLRC(
        _ source: String,
        undoManager: UndoManager? = nil
    ) -> Bool {
        guard
            let trackID = lyricDraft?.trackID,
            let document = try? LineLevelLRC.parse(
                source,
                trackID: trackID
            )
        else {
            return false
        }
        replaceLyricDraftDocument(
            document,
            actionName: "Import LRC",
            undoManager: undoManager
        )
        return true
    }

    func clearLyricTimestamps(
        undoManager: UndoManager? = nil
    ) {
        updateLyricDraft(
            actionName: "Clear Lyric Timing",
            undoManager: undoManager
        ) { draft in
            guard draft.lines.contains(where: { $0.startTime != nil }) else {
                return false
            }
            for index in draft.lines.indices {
                draft.lines[index].startTime = nil
            }
            return true
        }
    }

    func stampActiveLyricLine(
        undoManager: UndoManager? = nil
    ) {
        guard let draft = lyricDraft else {
            return
        }
        let playbackTime: TimeInterval
        switch draft.trackID {
        case .preview:
            guard let currentTrack else {
                return
            }
            playbackTime = currentTrack.duration * progress
        case let .managed(trackID):
            guard currentPlaybackTrack?.id == trackID else {
                return
            }
            playbackTime = playbackCurrentTime
        }
        updateLyricDraft(
            actionName: "Stamp Lyric Line",
            undoManager: undoManager
        ) { draft in
            draft.stampActiveLine(at: playbackTime)
        }
    }

    func moveActiveLyricLine(by offset: Int) {
        guard var draft = lyricDraft else {
            return
        }
        draft.moveActiveLine(by: offset)
        lyricDraft = draft
    }

    private func replaceLyricDraftLines(
        _ lines: [LyricLine],
        actionName: String,
        undoManager: UndoManager?
    ) {
        updateLyricDraft(
            actionName: actionName,
            undoManager: undoManager
        ) { draft in
            guard draft.lines != lines else {
                return false
            }
            draft.lines = lines
            draft.activeLineID = lines.first(where: { !$0.isBlank })?.id
                ?? lines.first?.id
            return true
        }
    }

    private func replaceLyricDraftDocument(
        _ document: LyricDocument,
        actionName: String,
        undoManager: UndoManager?
    ) {
        updateLyricDraft(
            actionName: actionName,
            undoManager: undoManager
        ) { draft in
            guard
                draft.lines != document.lines
                || draft.metadataLines != document.metadataLines
            else {
                return false
            }
            draft.lines = document.lines
            draft.metadataLines = document.metadataLines
            draft.activeLineID = document.lines.first {
                !$0.isBlank
            }?.id ?? document.lines.first?.id
            return true
        }
    }

    private func updateLyricDraft(
        actionName: String,
        undoManager: UndoManager?,
        mutation: (inout LyricDraft) -> Bool
    ) {
        guard var draft = lyricDraft else {
            return
        }
        let previous = draft
        guard mutation(&draft) else {
            return
        }
        lyricDraft = draft
        registerLyricDraftUndo(
            restoring: previous,
            actionName: actionName,
            undoManager: undoManager
        )
    }

    private func registerLyricDraftUndo(
        restoring snapshot: LyricDraft,
        actionName: String,
        undoManager: UndoManager?
    ) {
        guard let undoManager else {
            return
        }
        undoManager.registerUndo(withTarget: self) { model in
            guard let redoSnapshot = model.lyricDraft else {
                return
            }
            model.lyricDraft = snapshot
            model.registerLyricDraftUndo(
                restoring: redoSnapshot,
                actionName: actionName,
                undoManager: undoManager
            )
        }
        undoManager.setActionName(actionName)
    }
}
