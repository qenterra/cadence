@testable import Cadence
import Foundation
import Testing

struct LyricsTimelineTests {
    @Test("Paused playback emits the current line without scheduling a wake")
    func pausedPlaybackStopsScheduling() {
        let (timeline, lines) = makeTimeline(times: [4, 8, 12])

        let paused = LyricObservationPolicy.step(
            timeline: timeline,
            presentationTime: 6,
            isAdvancing: false
        )
        let advancing = LyricObservationPolicy.step(
            timeline: timeline,
            presentationTime: 6,
            isAdvancing: true
        )

        #expect(paused.activeLineID == lines[0].id)
        #expect(paused.nextUpdateAfter == nil)
        #expect(advancing.activeLineID == lines[0].id)
        #expect(advancing.nextUpdateAfter == 2)
    }

    @Test("Lyrics schedule only the first strictly later boundary")
    func exactBoundarySchedule() {
        let (timeline, lines) = makeTimeline(times: [4, 8, 12])

        #expect(
            LyricObservationPolicy.step(
                timeline: timeline,
                presentationTime: 2,
                isAdvancing: true
            ) == LyricObservationStep(
                activeLineID: nil,
                nextUpdateAfter: 2
            )
        )
        #expect(
            LyricObservationPolicy.step(
                timeline: timeline,
                presentationTime: 4,
                isAdvancing: true
            ) == LyricObservationStep(
                activeLineID: lines[0].id,
                nextUpdateAfter: 4
            )
        )
        #expect(
            LyricObservationPolicy.step(
                timeline: timeline,
                presentationTime: 8,
                isAdvancing: true
            ) == LyricObservationStep(
                activeLineID: lines[1].id,
                nextUpdateAfter: 4
            )
        )
        #expect(
            LyricObservationPolicy.step(
                timeline: timeline,
                presentationTime: 12,
                isAdvancing: true
            ) == LyricObservationStep(
                activeLineID: lines[2].id,
                nextUpdateAfter: nil
            )
        )
    }

    @Test("Repeated timestamps activate the last ID at that boundary")
    func repeatedTimestampSchedule() {
        let (repeatedTimeline, repeatedLines) = makeTimeline(
            times: [4, 4, 8]
        )

        #expect(
            LyricObservationPolicy.step(
                timeline: repeatedTimeline,
                presentationTime: 4,
                isAdvancing: true
            ) == LyricObservationStep(
                activeLineID: repeatedLines[1].id,
                nextUpdateAfter: 4
            )
        )
    }

    @Test("Repeated candidates emit only when the optional line ID changes")
    func lineIDEmissionDeduplicatesRestarts() {
        let first = UUID()
        let second = UUID()
        var state = LyricLineEmissionState()
        let candidates: [LyricLine.ID?] = [
            nil,
            first,
            first,
            first,
            second,
            second,
            nil,
            nil,
        ]

        let emissions = candidates.map { state.update(to: $0) }

        #expect(emissions == [
            false,
            true,
            false,
            false,
            true,
            false,
            true,
            false,
        ])
        #expect(state.activeLineID == nil)
    }

    @Test("Legacy lyrics frame clocks and blur do not return")
    func legacyObserverSourceSmoke() throws {
        let source = try productionLyricsPanelSource()

        #expect(!source.contains("TimelineView(.animation"))
        #expect(!source.contains("1.0 / 120.0"))
        #expect(!source.contains(".blur("))
    }

    @Test("Non-finite lyric boundary deltas never reach the scheduler")
    func nonFiniteBoundaryDoesNotSchedule() {
        let (timeline, lines) = makeTimeline(times: [4, .infinity])

        let step = LyricObservationPolicy.step(
            timeline: timeline,
            presentationTime: 6,
            isAdvancing: true
        )

        #expect(step.activeLineID == lines[0].id)
        #expect(step.nextUpdateAfter == nil)
    }

    @Test("Non-finite presentation times never schedule a wake")
    func nonFinitePresentationTimesDoNotSchedule() {
        let (timeline, lines) = makeTimeline(times: [4, 8, 12])

        let notANumber = LyricObservationPolicy.step(
            timeline: timeline,
            presentationTime: .nan,
            isAdvancing: true
        )
        let positiveInfinity = LyricObservationPolicy.step(
            timeline: timeline,
            presentationTime: .infinity,
            isAdvancing: true
        )
        let negativeInfinity = LyricObservationPolicy.step(
            timeline: timeline,
            presentationTime: -.infinity,
            isAdvancing: true
        )

        #expect(notANumber.activeLineID == nil)
        #expect(notANumber.nextUpdateAfter == nil)
        #expect(positiveInfinity.activeLineID == lines[2].id)
        #expect(positiveInfinity.nextUpdateAfter == nil)
        #expect(negativeInfinity.activeLineID == nil)
        #expect(negativeInfinity.nextUpdateAfter == nil)
    }
}

extension LyricsTimelineTests {
    @MainActor
    @Test("A delayed older load cannot replace the accepted document")
    func delayedOutOfOrderLoadKeepsLatestDocument() async {
        let loader = DelayedLyricDocumentLoader()
        let harness = LyricDocumentLoadHarness()
        let trackA = UUID()
        let trackB = UUID()
        let documentA = makeDocument(trackID: trackA, text: "Old")
        let documentB = makeDocument(trackID: trackB, text: "Current")

        let loadA = Task { @MainActor in
            await harness.load(
                trackID: trackA,
                lyricsRevision: 4,
                from: loader
            )
        }
        await loader.waitUntilRequested(trackID: trackA)

        let loadB = Task { @MainActor in
            await harness.load(
                trackID: trackB,
                lyricsRevision: 4,
                from: loader
            )
        }
        await loader.waitUntilRequested(trackID: trackB)

        await loader.complete(trackID: trackB, with: documentB)
        #expect(await loadB.value)
        let acceptedGeneration = harness.state.acceptedGeneration

        await loader.complete(trackID: trackA, with: documentA)
        let staleLoadWasAccepted = await loadA.value
        #expect(!staleLoadWasAccepted)
        #expect(harness.state.document == documentB)
        #expect(harness.state.acceptedGeneration == acceptedGeneration)
    }

    @MainActor
    @Test("A cancelled delayed load cannot publish its document")
    func cancelledDelayedLoadIsRejected() async {
        let loader = DelayedLyricDocumentLoader()
        let harness = LyricDocumentLoadHarness()
        let trackID = UUID()
        let document = makeDocument(trackID: trackID, text: "Cancelled")

        let load = Task { @MainActor in
            await harness.load(
                trackID: trackID,
                lyricsRevision: 7,
                from: loader
            )
        }
        await loader.waitUntilRequested(trackID: trackID)
        load.cancel()
        await loader.complete(trackID: trackID, with: document)

        let cancelledLoadWasAccepted = await load.value
        #expect(!cancelledLoadWasAccepted)
        #expect(harness.state.document == nil)
        #expect(harness.state.acceptedGeneration == nil)
    }

    @Test("Loads reject wrong tracks, wrong revisions, and wrong documents")
    func loadAcceptanceRequiresExactRequestContext() {
        let requestedTrackID = UUID()
        let otherTrackID = UUID()
        let requestedDocument = makeDocument(
            trackID: requestedTrackID,
            text: "Requested"
        )
        let wrongDocument = makeDocument(
            trackID: otherTrackID,
            text: "Wrong"
        )

        var wrongCurrentTrack = LyricDocumentPresentationState()
        let trackRequest = wrongCurrentTrack.beginLoad(
            trackID: requestedTrackID,
            lyricsRevision: 3
        )
        let acceptedWrongCurrentTrack = wrongCurrentTrack.acceptLoad(
            requestedDocument,
            for: trackRequest,
            currentTrackID: otherTrackID,
            currentLyricsRevision: 3,
            isCancelled: false,
            presentationTime: 0
        )
        #expect(!acceptedWrongCurrentTrack)

        var wrongRevision = LyricDocumentPresentationState()
        let revisionRequest = wrongRevision.beginLoad(
            trackID: requestedTrackID,
            lyricsRevision: 3
        )
        let acceptedWrongRevision = wrongRevision.acceptLoad(
            requestedDocument,
            for: revisionRequest,
            currentTrackID: requestedTrackID,
            currentLyricsRevision: 4,
            isCancelled: false,
            presentationTime: 0
        )
        #expect(!acceptedWrongRevision)

        var wrongDocumentTrack = LyricDocumentPresentationState()
        let documentRequest = wrongDocumentTrack.beginLoad(
            trackID: requestedTrackID,
            lyricsRevision: 3
        )
        let acceptedWrongDocument = wrongDocumentTrack.acceptLoad(
            wrongDocument,
            for: documentRequest,
            currentTrackID: requestedTrackID,
            currentLyricsRevision: 3,
            isCancelled: false,
            presentationTime: 0
        )
        #expect(!acceptedWrongDocument)
    }

    @Test("Beginning a replacement clears the accepted document and line")
    func replacementLoadClearsTrackStateBeforeSuspension() throws {
        let trackA = UUID()
        let trackB = UUID()
        let documentA = makeDocument(trackID: trackA, text: "Old")
        var state = LyricDocumentPresentationState()
        let requestA = state.beginLoad(trackID: trackA, lyricsRevision: 1)
        let acceptedA = state.acceptLoad(
            documentA,
            for: requestA,
            currentTrackID: trackA,
            currentLyricsRevision: 1,
            isCancelled: false,
            presentationTime: 4
        )
        #expect(acceptedA)
        let oldLineID = try #require(documentA.lines.first?.id)
        #expect(state.activeLineID == oldLineID)

        let requestB = state.beginLoad(trackID: trackB, lyricsRevision: 1)

        #expect(requestB.trackID == trackB)
        #expect(state.document == nil)
        #expect(state.acceptedGeneration == nil)
        #expect(state.activeLineID == nil)
    }

    @Test("Accepted generations restart an otherwise identical observer key")
    func acceptedGenerationParticipatesInObserverIdentity() {
        let trackID = UUID()
        let first = PlaybackLyricObservationKey(
            expectedTrackID: trackID,
            currentTrackID: trackID,
            playbackAnchor: 4,
            isAdvancing: true,
            acceptedDocumentGeneration: 1
        )
        let replacement = PlaybackLyricObservationKey(
            expectedTrackID: trackID,
            currentTrackID: trackID,
            playbackAnchor: 4,
            isAdvancing: true,
            acceptedDocumentGeneration: 2
        )

        #expect(first != replacement)
    }

    @Test("Accepted presentation rejects stale identity before a new load begins")
    func acceptedPresentationRequiresExactRenderIdentity() {
        let trackA = UUID()
        let trackB = UUID()
        let documentA = makeDocument(trackID: trackA, text: "Old")
        var state = LyricDocumentPresentationState()
        let requestA = state.beginLoad(trackID: trackA, lyricsRevision: 1)
        let acceptedA = state.acceptLoad(
            documentA,
            for: requestA,
            currentTrackID: trackA,
            currentLyricsRevision: 1,
            isCancelled: false,
            presentationTime: 4
        )
        #expect(acceptedA)

        #expect(state.acceptedPresentation(
            expectedTrackID: trackB,
            currentTrackID: trackB,
            currentLyricsRevision: 1,
            isExternal: false
        ) == nil)
        #expect(state.acceptedPresentation(
            expectedTrackID: trackA,
            currentTrackID: trackA,
            currentLyricsRevision: 2,
            isExternal: false
        ) == nil)
        #expect(state.acceptedPresentation(
            expectedTrackID: trackA,
            currentTrackID: trackA,
            currentLyricsRevision: 1,
            isExternal: false
        )?.document == documentA)
    }

    @Test("Accepted presentation requires the current managed playback context")
    func acceptedPresentationRejectsExternalOrNoncurrentPlayback() {
        let trackID = UUID()
        let otherTrackID = UUID()
        let document = makeDocument(trackID: trackID, text: "Managed")
        var state = LyricDocumentPresentationState()
        let request = state.beginLoad(trackID: trackID, lyricsRevision: 3)
        let accepted = state.acceptLoad(
            document,
            for: request,
            currentTrackID: trackID,
            currentLyricsRevision: 3,
            isCancelled: false,
            presentationTime: 4
        )
        #expect(accepted)

        #expect(state.acceptedPresentation(
            expectedTrackID: trackID,
            currentTrackID: otherTrackID,
            currentLyricsRevision: 3,
            isExternal: false
        ) == nil)
        #expect(state.acceptedPresentation(
            expectedTrackID: trackID,
            currentTrackID: trackID,
            currentLyricsRevision: 3,
            isExternal: true
        ) == nil)
    }

    @Test("An old observer generation cannot write a reused line ID")
    func activeLineWriteRequiresCurrentAcceptedGeneration() throws {
        let trackID = UUID()
        let reusedLineID = UUID()
        let currentLineID = UUID()
        let oldDocument = LyricDocument(
            trackID: trackID,
            lines: [
                LyricLine(
                    id: reusedLineID,
                    text: "Old observer target",
                    startTime: 0
                ),
            ]
        )
        let replacementDocument = LyricDocument(
            trackID: trackID,
            lines: [
                LyricLine(
                    id: currentLineID,
                    text: "Current target",
                    startTime: 0
                ),
                LyricLine(
                    id: reusedLineID,
                    text: "Reused later target",
                    startTime: 10
                ),
            ]
        )
        var state = LyricDocumentPresentationState()
        let oldRequest = state.beginLoad(trackID: trackID, lyricsRevision: 1)
        let acceptedOldDocument = state.acceptLoad(
            oldDocument,
            for: oldRequest,
            currentTrackID: trackID,
            currentLyricsRevision: 1,
            isCancelled: false,
            presentationTime: 4
        )
        #expect(acceptedOldDocument)
        let oldGeneration = try #require(state.acceptedGeneration)

        let replacementRequest = state.beginLoad(
            trackID: trackID,
            lyricsRevision: 2
        )
        let acceptedReplacement = state.acceptLoad(
            replacementDocument,
            for: replacementRequest,
            currentTrackID: trackID,
            currentLyricsRevision: 2,
            isCancelled: false,
            presentationTime: 4
        )
        #expect(acceptedReplacement)
        let replacementGeneration = try #require(state.acceptedGeneration)
        #expect(state.activeLineID == currentLineID)

        let acceptedOldWrite = state.updateActiveLineID(
            reusedLineID,
            fromAcceptedGeneration: oldGeneration
        )
        #expect(!acceptedOldWrite)
        #expect(state.activeLineID == currentLineID)
        let acceptedCurrentWrite = state.updateActiveLineID(
            reusedLineID,
            fromAcceptedGeneration: replacementGeneration
        )
        #expect(acceptedCurrentWrite)
        #expect(state.activeLineID == reusedLineID)
    }

    @Test("A delayed inline edit cannot replace a newer document generation")
    func delayedInlineEditPublicationIsGenerationGuarded() throws {
        let trackA = UUID()
        let trackB = UUID()
        let documentA = makeDocument(trackID: trackA, text: "Old")
        let documentB = makeDocument(trackID: trackB, text: "Current")
        var state = LyricDocumentPresentationState()
        let requestA = state.beginLoad(trackID: trackA, lyricsRevision: 2)
        let acceptedA = state.acceptLoad(
            documentA,
            for: requestA,
            currentTrackID: trackA,
            currentLyricsRevision: 2,
            isCancelled: false,
            presentationTime: 4
        )
        #expect(acceptedA)
        let lineA = try #require(documentA.lines.first)
        let edit = try #require(state.editRequest(lineID: lineA.id))

        let requestB = state.beginLoad(trackID: trackB, lyricsRevision: 2)
        let acceptedB = state.acceptLoad(
            documentB,
            for: requestB,
            currentTrackID: trackB,
            currentLyricsRevision: 2,
            isCancelled: false,
            presentationTime: 4
        )
        #expect(acceptedB)
        let editedA = try #require(
            documentA.replacingText(for: lineA.id, with: "Too late")
        )

        let publishedStaleEdit = state.publishEditedDocument(
            editedA,
            for: edit,
            currentTrackID: trackB,
            currentLyricsRevision: 3,
            isCancelled: false
        )
        #expect(!publishedStaleEdit)
        #expect(state.document == documentB)
    }

    @Test("An exact inline edit publishes as a new accepted generation")
    func exactInlineEditAdvancesAcceptedGeneration() throws {
        let trackID = UUID()
        let document = makeDocument(trackID: trackID, text: "Before")
        var state = LyricDocumentPresentationState()
        let load = state.beginLoad(trackID: trackID, lyricsRevision: 8)
        let accepted = state.acceptLoad(
            document,
            for: load,
            currentTrackID: trackID,
            currentLyricsRevision: 8,
            isCancelled: false,
            presentationTime: 4
        )
        #expect(accepted)
        let sourceGeneration = try #require(state.acceptedGeneration)
        let line = try #require(document.lines.first)
        let edit = try #require(state.editRequest(lineID: line.id))
        let updated = try #require(
            document.replacingText(for: line.id, with: "After")
        )

        let published = state.publishEditedDocument(
            updated,
            for: edit,
            currentTrackID: trackID,
            currentLyricsRevision: 9,
            isCancelled: false
        )
        #expect(published)
        #expect(state.document == updated)
        #expect(state.acceptedGeneration != sourceGeneration)
        #expect(state.acceptedRequest?.lyricsRevision == 9)
    }
}

private extension LyricsTimelineTests {
    private func makeTimeline(
        times: [TimeInterval]
    ) -> (timeline: SynchronizedLyricTimeline, lines: [LyricLine]) {
        let lines = times.enumerated().map { index, time in
            LyricLine(text: "Line \(index + 1)", startTime: time)
        }
        let document = LyricDocument(trackID: UUID(), lines: lines)
        return (SynchronizedLyricTimeline(document: document), lines)
    }

    private func makeDocument(
        trackID: UUID,
        text: String
    ) -> LyricDocument {
        LyricDocument(
            trackID: trackID,
            lines: [LyricLine(text: text, startTime: 4)]
        )
    }

    private func productionLyricsPanelSource() throws -> String {
        let sourceURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(
                path: "Sources/Cadence/Features/NowPlaying/ProductionLyricsPanel.swift"
            )
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

@MainActor
private final class LyricDocumentLoadHarness {
    private(set) var state = LyricDocumentPresentationState()
    private var currentTrackID: UUID?
    private var currentLyricsRevision = 0

    func load(
        trackID: UUID,
        lyricsRevision: Int,
        from loader: DelayedLyricDocumentLoader
    ) async -> Bool {
        currentTrackID = trackID
        currentLyricsRevision = lyricsRevision
        let request = state.beginLoad(
            trackID: trackID,
            lyricsRevision: lyricsRevision
        )
        let document = await loader.load(trackID: trackID)
        return state.acceptLoad(
            document,
            for: request,
            currentTrackID: currentTrackID,
            currentLyricsRevision: currentLyricsRevision,
            isCancelled: Task.isCancelled,
            presentationTime: 4
        )
    }
}

private actor DelayedLyricDocumentLoader {
    private var loads: [UUID: CheckedContinuation<LyricDocument?, Never>] = [:]
    private var requestWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func load(trackID: UUID) async -> LyricDocument? {
        await withCheckedContinuation { continuation in
            precondition(loads[trackID] == nil)
            loads[trackID] = continuation
            let waiters = requestWaiters.removeValue(forKey: trackID) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilRequested(trackID: UUID) async {
        guard loads[trackID] == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            requestWaiters[trackID, default: []].append(continuation)
        }
    }

    func complete(trackID: UUID, with document: LyricDocument?) {
        guard let continuation = loads.removeValue(forKey: trackID) else {
            preconditionFailure("No delayed lyric load exists for \(trackID)")
        }
        continuation.resume(returning: document)
    }
}

struct LyricsDomainTests {
    @Test("A lyric line can be replaced without changing timing or identity")
    func replacingLineText() throws {
        let line = LyricLine(text: "Before", startTime: 12.5)
        let document = LyricDocument(trackID: UUID(), lines: [line])

        let updated = try #require(
            document.replacingText(
                for: line.id,
                with: "  After  "
            )
        )

        #expect(updated.lines[0].id == line.id)
        #expect(updated.lines[0].startTime == 12.5)
        #expect(updated.lines[0].text == "After")
        #expect(document.lines[0].text == "Before")
        #expect(document.replacingText(for: UUID(), with: "Missing") == nil)
    }

    @Test("Timing status distinguishes every supported lyric state")
    func timingStatus() {
        #expect(LyricDocument(trackID: 1, lines: []).timingStatus == .missing)
        #expect(
            document(
                texts: ["First", "", "Second"],
                times: [nil, nil, nil]
            ).timingStatus == .unsynchronized
        )
        #expect(
            document(
                texts: ["First", "Second"],
                times: [1, nil]
            ).timingStatus == .partiallySynchronized
        )
        #expect(
            document(
                texts: ["First", "", "Second"],
                times: [1, nil, 3]
            ).timingStatus == .synchronized
        )
    }

    @Test("Active line lookup uses line timestamps and their boundaries")
    func activeLineLookup() throws {
        let lyrics = document(
            texts: ["First", "Second", "Third"],
            times: [4, 8, 12]
        )
        let first = try #require(lyrics.lines.first)
        let second = try #require(lyrics.lines.dropFirst().first)
        let third = try #require(lyrics.lines.last)

        #expect(lyrics.activeLine(at: 0) == nil)
        #expect(lyrics.activeLine(at: 4)?.id == first.id)
        #expect(lyrics.activeLine(at: 7.99)?.id == first.id)
        #expect(lyrics.activeLine(at: 8)?.id == second.id)
        #expect(lyrics.activeLine(at: 999)?.id == third.id)
    }

    @Test("Compiled lyric timeline keeps exact timestamp boundaries")
    func compiledTimelineLookup() {
        let lyrics = document(
            texts: ["First", "Second", "Third"],
            times: [4, 8, 12]
        )
        let timeline = SynchronizedLyricTimeline(document: lyrics)

        #expect(timeline.activeLineID(at: 3.99) == nil)
        #expect(timeline.activeLineID(at: 4) == lyrics.lines[0].id)
        #expect(timeline.activeLineID(at: 11.99) == lyrics.lines[1].id)
        #expect(timeline.activeLineID(at: 12) == lyrics.lines[2].id)
    }

    @Test("Timestamp validation allows missing stanza times and reports exact rows")
    func validation() {
        let lyrics = document(
            texts: ["Negative", "", "Late", "Backwards"],
            times: [-1, nil, 13, 8]
        )
        let issues = lyrics.validationIssues(trackDuration: 10)

        #expect(issues.map(\.lineID) == [
            lyrics.lines[0].id,
            lyrics.lines[2].id,
            lyrics.lines[3].id,
        ])
        #expect(issues.map(\.kind) == [
            .negative,
            .exceedsTrackDuration,
            .decreasing,
        ])
    }

    @Test("Non-finite timestamps are rejected")
    func nonFiniteValidation() {
        let lyrics = document(
            texts: ["NaN", "Infinity"],
            times: [.nan, .infinity]
        )

        #expect(lyrics.validationIssues(trackDuration: 100).map(\.kind) == [
            .nonFinite,
            .nonFinite,
        ])
    }

    @Test("Plain text creates one line per source line and preserves stanzas")
    func plainText() {
        let lines = LyricDocument.lines(fromPlainText: "First\n\nThird")

        #expect(lines.map(\.text) == ["First", "", "Third"])
        #expect(lines.allSatisfy { $0.startTime == nil })
    }

    @Test("Line-level LRC parses metadata, timestamps, and stanza rows")
    func lrcParsing() throws {
        let source = """
        [ar:North Assembly]
        [00:04.20]First line

        [00:08.005]Second line
        """

        let document = try LineLevelLRC.parse(source, trackID: 7)

        #expect(document.lines.map(\.text) == ["First line", "", "Second line"])
        #expect(document.lines[0].startTime == 4.2)
        #expect(document.lines[1].startTime == nil)
        #expect(document.lines[2].startTime == 8.005)
        #expect(document.metadataLines == ["[ar:North Assembly]"])
    }

    @Test("Malformed timestamp fails without returning partial content")
    func malformedLRC() {
        #expect(throws: LineLevelLRC.Error.self) {
            try LineLevelLRC.parse(
                "[00:04.20]Valid\n[00:99.000]Nope",
                trackID: 8
            )
        }
    }

    @Test("LRC generation is line-level and round trips synchronized lyrics")
    func lrcGeneration() throws {
        let original = document(
            trackID: 9,
            texts: ["First", "", "Second"],
            times: [4.2, nil, 68.005]
        )

        let output = try LineLevelLRC.generate(original)
        let parsed = try LineLevelLRC.parse(output, trackID: 9)

        #expect(output == "[00:04.200]First\n\n[01:08.005]Second\n")
        #expect(parsed.lines.map(\.text) == original.lines.map(\.text))
        #expect(parsed.lines.map(\.startTime) == original.lines.map(\.startTime))
    }

    @Test("Partial lyrics round trip timed and untimed lines")
    func partialGeneration() throws {
        let lyrics = document(
            texts: ["First", "Second"],
            times: [1, nil]
        )

        let output = try LineLevelLRC.generate(lyrics)
        let parsed = try LineLevelLRC.parse(output, trackID: 1)

        #expect(output == "[00:01.000]First\nSecond\n")
        #expect(parsed.timingStatus == .partiallySynchronized)
        #expect(parsed.lines.map(\.text) == ["First", "Second"])
        #expect(parsed.lines.map(\.startTime) == [1, nil])
    }

    @Test("Metadata and repeated timestamps survive parsing and generation")
    func metadataAndRepeatedTimestamps() throws {
        let source = """
        [ar:North Assembly]
        [al:Signals]
        [00:01.00][00:03.500]Echo
        Untimed
        """

        let document = try LineLevelLRC.parse(source, trackID: 1)
        let output = try LineLevelLRC.generate(document)

        #expect(document.metadataLines == [
            "[ar:North Assembly]",
            "[al:Signals]",
        ])
        #expect(document.lines.map(\.text) == ["Echo", "Echo", "Untimed"])
        #expect(document.lines.map(\.startTime) == [1, 3.5, nil])
        #expect(
            output
                == """
                [ar:North Assembly]
                [al:Signals]
                [00:01.000]Echo
                [00:03.500]Echo
                Untimed

                """
        )
    }

    @Test("Timestamp formatting is deterministic")
    func formatting() {
        #expect(LyricTimestampFormatter.display(68.005) == "1:08.005")
        #expect(LyricTimestampFormatter.lrc(68.005) == "01:08.005")
    }

    private func document(
        trackID: TrackPreview.ID = 1,
        texts: [String],
        times: [TimeInterval?]
    ) -> LyricDocument {
        LyricDocument(
            trackID: trackID,
            lines: zip(texts, times).map { text, time in
                LyricLine(text: text, startTime: time)
            }
        )
    }
}
