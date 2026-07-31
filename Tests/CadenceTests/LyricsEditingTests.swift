@testable import Cadence
import Foundation
import Testing

@MainActor
struct LyricsEditingTests {
    @Test("Editor creates isolated drafts for existing and missing lyrics")
    func draftCreation() throws {
        let model = CadenceAppModel.testFixture()
        let savedDocument = try #require(model.currentLyricDocument)

        #expect(model.presentLyricsEditor())
        #expect(model.lyricDraft?.lines == savedDocument.lines)
        #expect(!model.isLyricDraftDirty)

        let missingTrack = try #require(
            model.tracks.first { model.lyricDocuments[$0.id] == nil }
        )
        model.currentTrackID = missingTrack.id
        model.presentLyricsEditor()

        #expect(model.lyricDraft?.trackID == .preview(missingTrack.id))
        #expect(model.lyricDraft?.lines.count == 1)
        #expect(model.lyricDraft?.document.timingStatus == .missing)
    }

    @Test("Text, row, and timestamp operations mutate only the draft")
    func draftMutations() throws {
        let model = CadenceAppModel.testFixture()
        let track = try #require(model.currentTrack)
        let savedText = model.lyricDocuments[track.id]?.lines.first?.text
        model.presentLyricsEditor()
        let firstLine = try #require(model.lyricDraft?.lines.first)

        model.updateLyricText(lineID: firstLine.id, text: "Draft")
        model.addLyricLine(after: firstLine.id)
        let addedLine = try #require(
            model.lyricDraft?.lines.first { $0.id != firstLine.id }
        )
        model.updateLyricTimestamp(
            lineID: addedLine.id,
            startTime: 30
        )

        #expect(model.isLyricDraftDirty)
        #expect(model.lyricDocuments[track.id]?.lines.first?.text == savedText)
        #expect(
            model.lyricDraft?.lines.first {
                $0.id == addedLine.id
            }?.startTime == 30
        )
    }

    @Test("Tap to Sync stamps mock playback time and advances")
    func tapToSync() throws {
        let model = CadenceAppModel.testFixture()
        let track = try #require(model.currentTrack)
        model.presentLyricsEditor()
        let lines = try #require(model.lyricDraft?.lines.filter { !$0.isBlank })
        let first = try #require(lines.first)
        let second = try #require(lines.dropFirst().first)
        model.activateLyricLine(first.id)
        model.progress = 0.5

        model.stampActiveLyricLine()

        #expect(
            model.lyricDraft?.lines.first {
                $0.id == first.id
            }?.startTime == track.duration * 0.5
        )
        #expect(model.lyricDraft?.activeLineID == second.id)
    }

    @Test("Clear timing preserves lyric text")
    func clearTiming() throws {
        let model = CadenceAppModel.testFixture()
        model.presentLyricsEditor()
        let texts = try #require(model.lyricDraft?.lines.map(\.text))

        model.clearLyricTimestamps()

        #expect(model.lyricDraft?.lines.map(\.text) == texts)
        #expect(
            model.lyricDraft?.lines.allSatisfy {
                $0.startTime == nil
            } == true
        )
        #expect(model.lyricDraft?.document.timingStatus == .unsynchronized)
    }

    @Test("Blocking timestamp errors prevent Save")
    func invalidSave() throws {
        let model = CadenceAppModel.testFixture()
        let track = try #require(model.currentTrack)
        model.presentLyricsEditor()
        let firstLine = try #require(model.lyricDraft?.lines.first)
        model.updateLyricTimestamp(
            lineID: firstLine.id,
            startTime: track.duration + 1
        )

        #expect(!model.lyricDraftValidationIssues.isEmpty)
        #expect(!model.canSaveLyricDraft)
        #expect(!model.saveLyricDraft())
    }

    @Test("LRC replacement is atomic when parsing fails")
    func atomicLRCImport() throws {
        let model = CadenceAppModel.testFixture()
        model.presentLyricsEditor()
        let originalLines = try #require(model.lyricDraft?.lines)

        #expect(!model.replaceLyricDraftWithLRC("[00:99.000]broken"))
        #expect(model.lyricDraft?.lines == originalLines)

        #expect(
            model.replaceLyricDraftWithLRC(
                "[00:01.000]First\n[00:02.000]Second"
            )
        )
        #expect(model.lyricDraft?.lines.map(\.text) == ["First", "Second"])
    }

    @Test("Structural draft edits register one-step Undo")
    func structuralUndo() throws {
        let model = CadenceAppModel.testFixture()
        let undoManager = UndoManager()
        model.presentLyricsEditor()
        let originalLines = try #require(model.lyricDraft?.lines)

        model.addLyricLine(undoManager: undoManager)
        #expect(model.lyricDraft?.lines.count == originalLines.count + 1)

        undoManager.undo()
        #expect(model.lyricDraft?.lines == originalLines)
    }
}
