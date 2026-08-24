import Foundation

enum LyricTrackIdentity: Hashable, Sendable {
    case preview(TrackPreview.ID)
    case managed(UUID)
}

struct LyricLine: Identifiable, Hashable, Sendable {
    let id: UUID
    var text: String
    var startTime: TimeInterval?

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
    }

    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum LyricTimingStatus: String, Codable, Hashable, Sendable {
    case missing
    case unsynchronized
    case partiallySynchronized
    case synchronized
}

struct LyricValidationIssue: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case negative
        case nonFinite
        case exceedsTrackDuration
        case decreasing
    }

    let lineID: LyricLine.ID
    let kind: Kind

    var id: LyricLine.ID {
        lineID
    }

    var message: String {
        switch kind {
        case .negative:
            String(localized: "Time cannot be negative.")
        case .nonFinite:
            String(localized: "Enter a valid time.")
        case .exceedsTrackDuration:
            String(localized: "Time exceeds the track duration.")
        case .decreasing:
            String(localized: "Time must not precede the previous lyric.")
        }
    }
}

struct LyricDocument: Hashable, Sendable {
    let trackID: LyricTrackIdentity
    var lines: [LyricLine]
    var metadataLines: [String]

    init(
        trackID: LyricTrackIdentity,
        lines: [LyricLine],
        metadataLines: [String] = []
    ) {
        self.trackID = trackID
        self.lines = lines
        self.metadataLines = metadataLines
    }

    init(
        trackID: TrackPreview.ID,
        lines: [LyricLine],
        metadataLines: [String] = []
    ) {
        self.init(
            trackID: .preview(trackID),
            lines: lines,
            metadataLines: metadataLines
        )
    }

    init(
        trackID: UUID,
        lines: [LyricLine],
        metadataLines: [String] = []
    ) {
        self.init(
            trackID: .managed(trackID),
            lines: lines,
            metadataLines: metadataLines
        )
    }

    var timingStatus: LyricTimingStatus {
        let contentLines = lines.filter { !$0.isBlank }
        guard !contentLines.isEmpty else {
            return .missing
        }

        let timedCount = contentLines.count { $0.startTime != nil }
        if timedCount == 0 {
            return .unsynchronized
        }
        if timedCount == contentLines.count {
            return .synchronized
        }
        return .partiallySynchronized
    }

    func activeLine(at time: TimeInterval) -> LyricLine? {
        guard let lineID = SynchronizedLyricTimeline(document: self)
            .activeLineID(at: time) else {
            return nil
        }
        return lines.first { $0.id == lineID }
    }

    func replacingText(
        for lineID: LyricLine.ID,
        with text: String
    ) -> LyricDocument? {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else {
            return nil
        }
        var updated = self
        updated.lines[index].text = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return updated
    }

    func validationIssues(
        trackDuration: TimeInterval
    ) -> [LyricValidationIssue] {
        var issues: [LyricValidationIssue] = []
        var previousTime: TimeInterval?

        for line in lines where !line.isBlank {
            guard let startTime = line.startTime else {
                continue
            }

            if !startTime.isFinite {
                issues.append(
                    LyricValidationIssue(
                        lineID: line.id,
                        kind: .nonFinite
                    )
                )
                continue
            }

            if startTime < 0 {
                issues.append(
                    LyricValidationIssue(
                        lineID: line.id,
                        kind: .negative
                    )
                )
                continue
            }

            if startTime > trackDuration {
                issues.append(
                    LyricValidationIssue(
                        lineID: line.id,
                        kind: .exceedsTrackDuration
                    )
                )
            }

            if let previousTime, startTime < previousTime {
                issues.append(
                    LyricValidationIssue(
                        lineID: line.id,
                        kind: .decreasing
                    )
                )
            }
            previousTime = startTime
        }
        return issues
    }

    static func lines(fromPlainText source: String) -> [LyricLine] {
        source
            .split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            .map { LyricLine(text: String($0)) }
    }
}

struct SynchronizedLyricTimeline: Sendable {
    private let entries: [(time: TimeInterval, id: LyricLine.ID)]

    init(document: LyricDocument) {
        let contentLines = document.lines.filter { !$0.isBlank }
        guard !contentLines.isEmpty,
              contentLines.allSatisfy({ $0.startTime != nil }) else {
            entries = []
            return
        }
        entries = contentLines.compactMap { line in
            line.startTime.map { (time: $0, id: line.id) }
        }
    }

    func activeLineID(at time: TimeInterval) -> LyricLine.ID? {
        observation(at: time).activeLineID
    }
}

struct SynchronizedLyricObservation: Equatable, Sendable {
    let activeLineID: LyricLine.ID?
    let nextBoundaryTime: TimeInterval?
}

extension SynchronizedLyricTimeline {
    func observation(
        at presentationTime: TimeInterval
    ) -> SynchronizedLyricObservation {
        var lower = 0
        var upper = entries.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if entries[middle].time <= presentationTime {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return SynchronizedLyricObservation(
            activeLineID: lower > 0 ? entries[lower - 1].id : nil,
            nextBoundaryTime: lower < entries.count
                ? entries[lower].time
                : nil
        )
    }
}

struct LyricObservationStep: Equatable, Sendable {
    let activeLineID: LyricLine.ID?
    let nextUpdateAfter: TimeInterval?
}

enum LyricObservationPolicy {
    static let minimumSleep: TimeInterval = 0.010

    static func step(
        timeline: SynchronizedLyricTimeline,
        presentationTime: TimeInterval,
        isAdvancing: Bool
    ) -> LyricObservationStep {
        let observation = timeline.observation(at: presentationTime)
        guard isAdvancing,
              let nextBoundaryTime = observation.nextBoundaryTime else {
            return LyricObservationStep(
                activeLineID: observation.activeLineID,
                nextUpdateAfter: nil
            )
        }

        let delay = nextBoundaryTime - presentationTime
        guard delay.isFinite else {
            return LyricObservationStep(
                activeLineID: observation.activeLineID,
                nextUpdateAfter: nil
            )
        }
        return LyricObservationStep(
            activeLineID: observation.activeLineID,
            nextUpdateAfter: max(delay, minimumSleep)
        )
    }
}

struct LyricLineEmissionState: Equatable, Sendable {
    private(set) var activeLineID: LyricLine.ID?

    init(activeLineID: LyricLine.ID? = nil) {
        self.activeLineID = activeLineID
    }

    @discardableResult
    mutating func update(
        to candidate: LyricLine.ID?
    ) -> Bool {
        guard candidate != activeLineID else {
            return false
        }
        activeLineID = candidate
        return true
    }
}

struct LyricMotionBehavior: Equatable, Sendable {
    let animatesEmphasis: Bool
    let animatesScroll: Bool

    static func resolve(
        reduceMotion: Bool
    ) -> LyricMotionBehavior {
        LyricMotionBehavior(
            animatesEmphasis: !reduceMotion,
            animatesScroll: !reduceMotion
        )
    }
}

enum LyricDocumentLineProjection {
    static func activeLineID(
        _ candidate: LyricLine.ID?,
        in document: LyricDocument
    ) -> LyricLine.ID? {
        guard let candidate,
              document.lines.contains(where: {
                  !$0.isBlank && $0.id == candidate
              }) else {
            return nil
        }
        return candidate
    }
}

struct LyricDocumentLoadRequest: Equatable, Sendable {
    let trackID: UUID
    let lyricsRevision: Int
    let generation: UInt64
}

struct AcceptedLyricDocument: Equatable, Sendable {
    let request: LyricDocumentLoadRequest
    let document: LyricDocument?
}

struct LyricDocumentEditRequest: Equatable, Sendable {
    let trackID: UUID
    let lineID: LyricLine.ID
    let sourceGeneration: UInt64
    let sourceLyricsRevision: Int
    let expectedLyricsRevision: Int
}

struct LyricDocumentPresentationState: Equatable, Sendable {
    private(set) var pendingRequest: LyricDocumentLoadRequest?
    private(set) var acceptedDocument: AcceptedLyricDocument?
    private(set) var activeLineID: LyricLine.ID?
    private var nextGeneration: UInt64 = 0

    var acceptedRequest: LyricDocumentLoadRequest? {
        acceptedDocument?.request
    }

    var acceptedGeneration: UInt64? {
        acceptedRequest?.generation
    }

    var document: LyricDocument? {
        acceptedDocument?.document
    }

    func acceptedPresentation(
        expectedTrackID: UUID,
        currentTrackID: UUID?,
        currentLyricsRevision: Int,
        isExternal: Bool
    ) -> AcceptedLyricDocument? {
        guard !isExternal,
              currentTrackID == expectedTrackID,
              acceptedDocument?.request.trackID == expectedTrackID,
              acceptedDocument?.request.lyricsRevision
              == currentLyricsRevision else {
            return nil
        }
        return acceptedDocument
    }

    @discardableResult
    mutating func beginLoad(
        trackID: UUID,
        lyricsRevision: Int
    ) -> LyricDocumentLoadRequest {
        let request = makeRequest(
            trackID: trackID,
            lyricsRevision: lyricsRevision
        )
        pendingRequest = request
        acceptedDocument = nil
        activeLineID = nil
        return request
    }

    @discardableResult
    mutating func acceptLoad(
        _ document: LyricDocument?,
        for request: LyricDocumentLoadRequest,
        currentTrackID: UUID?,
        currentLyricsRevision: Int,
        isCancelled: Bool,
        presentationTime: TimeInterval
    ) -> Bool {
        guard !isCancelled,
              pendingRequest == request,
              currentTrackID == request.trackID,
              currentLyricsRevision == request.lyricsRevision,
              documentBelongsToRequest(document, request: request) else {
            return false
        }

        pendingRequest = nil
        acceptedDocument = AcceptedLyricDocument(
            request: request,
            document: document
        )
        let candidate = document.flatMap {
            SynchronizedLyricTimeline(document: $0).activeLineID(
                at: presentationTime
            )
        }
        activeLineID = document.flatMap {
            LyricDocumentLineProjection.activeLineID(candidate, in: $0)
        }
        return true
    }

    @discardableResult
    mutating func updateActiveLineID(
        _ candidate: LyricLine.ID?,
        fromAcceptedGeneration sourceGeneration: UInt64
    ) -> Bool {
        guard acceptedGeneration == sourceGeneration else {
            return false
        }
        activeLineID = document.flatMap {
            LyricDocumentLineProjection.activeLineID(candidate, in: $0)
        }
        return true
    }

    func editRequest(
        lineID: LyricLine.ID
    ) -> LyricDocumentEditRequest? {
        guard let acceptedDocument,
              let document = acceptedDocument.document,
              document.lines.contains(where: { $0.id == lineID }) else {
            return nil
        }
        let nextRevision = acceptedDocument.request.lyricsRevision
            .addingReportingOverflow(1)
        guard !nextRevision.overflow else {
            return nil
        }
        return LyricDocumentEditRequest(
            trackID: acceptedDocument.request.trackID,
            lineID: lineID,
            sourceGeneration: acceptedDocument.request.generation,
            sourceLyricsRevision: acceptedDocument.request.lyricsRevision,
            expectedLyricsRevision: nextRevision.partialValue
        )
    }

    @discardableResult
    mutating func publishEditedDocument(
        _ document: LyricDocument,
        for edit: LyricDocumentEditRequest,
        currentTrackID: UUID?,
        currentLyricsRevision: Int,
        isCancelled: Bool
    ) -> Bool {
        guard !isCancelled,
              currentTrackID == edit.trackID,
              currentLyricsRevision == edit.expectedLyricsRevision,
              acceptedRequest?.trackID == edit.trackID,
              acceptedRequest?.lyricsRevision == edit.sourceLyricsRevision,
              acceptedGeneration == edit.sourceGeneration,
              document.trackID == .managed(edit.trackID),
              document.lines.contains(where: { $0.id == edit.lineID }) else {
            return false
        }

        let request = makeRequest(
            trackID: edit.trackID,
            lyricsRevision: currentLyricsRevision
        )
        pendingRequest = nil
        acceptedDocument = AcceptedLyricDocument(
            request: request,
            document: document
        )
        activeLineID = LyricDocumentLineProjection.activeLineID(
            activeLineID,
            in: document
        )
        return true
    }

    private mutating func makeRequest(
        trackID: UUID,
        lyricsRevision: Int
    ) -> LyricDocumentLoadRequest {
        nextGeneration += 1
        return LyricDocumentLoadRequest(
            trackID: trackID,
            lyricsRevision: lyricsRevision,
            generation: nextGeneration
        )
    }

    private func documentBelongsToRequest(
        _ document: LyricDocument?,
        request: LyricDocumentLoadRequest
    ) -> Bool {
        document == nil || document?.trackID == .managed(request.trackID)
    }
}

struct LyricDraft: Hashable, Sendable {
    let trackID: LyricTrackIdentity
    private(set) var savedLines: [LyricLine]
    private(set) var savedMetadataLines: [String]
    var lines: [LyricLine]
    var metadataLines: [String]
    var activeLineID: LyricLine.ID?

    init(
        trackID: LyricTrackIdentity,
        document: LyricDocument?
    ) {
        let sourceLines = document?.lines ?? [LyricLine(text: "")]
        self.trackID = trackID
        savedLines = sourceLines
        savedMetadataLines = document?.metadataLines ?? []
        lines = sourceLines
        metadataLines = document?.metadataLines ?? []
        activeLineID = sourceLines.first(where: { !$0.isBlank })?.id
            ?? sourceLines.first?.id
    }

    init(
        trackID: TrackPreview.ID,
        document: LyricDocument?
    ) {
        self.init(trackID: .preview(trackID), document: document)
    }

    init(
        trackID: UUID,
        document: LyricDocument?
    ) {
        self.init(trackID: .managed(trackID), document: document)
    }

    var isDirty: Bool {
        lines != savedLines || metadataLines != savedMetadataLines
    }

    var document: LyricDocument {
        LyricDocument(
            trackID: trackID,
            lines: lines,
            metadataLines: metadataLines
        )
    }

    mutating func markSaved() {
        savedLines = lines
        savedMetadataLines = metadataLines
    }

    @discardableResult
    mutating func stampActiveLine(at time: TimeInterval) -> Bool {
        guard
            let activeLineID,
            let index = lines.firstIndex(where: { $0.id == activeLineID })
        else {
            return false
        }

        lines[index].startTime = time
        let remaining = lines.indices.dropFirst(index + 1)
        self.activeLineID = remaining.first(where: { !lines[$0].isBlank })
            .map { lines[$0].id }
            ?? lines[index].id
        return true
    }

    mutating func moveActiveLine(by offset: Int) {
        guard
            let activeLineID,
            let currentIndex = lines.firstIndex(where: {
                $0.id == activeLineID
            })
        else {
            return
        }

        let contentIndices = lines.indices.filter { !lines[$0].isBlank }
        guard
            let position = contentIndices.firstIndex(of: currentIndex)
        else {
            return
        }
        let targetPosition = min(
            max(position + offset, contentIndices.startIndex),
            contentIndices.index(before: contentIndices.endIndex)
        )
        self.activeLineID = lines[contentIndices[targetPosition]].id
    }
}

enum LyricTimestampFormatter {
    static func display(_ time: TimeInterval) -> String {
        components(time).display
    }

    static func lrc(_ time: TimeInterval) -> String {
        components(time).lrc
    }

    private static func components(
        _ time: TimeInterval
    ) -> (display: String, lrc: String) {
        let milliseconds = max(Int((time * 1000).rounded()), 0)
        let minutes = milliseconds / 60000
        let seconds = (milliseconds / 1000) % 60
        let remainder = milliseconds % 1000

        return (
            "\(minutes):\(String(format: "%02d.%03d", seconds, remainder))",
            String(
                format: "%02d:%02d.%03d",
                minutes,
                seconds,
                remainder
            )
        )
    }
}
