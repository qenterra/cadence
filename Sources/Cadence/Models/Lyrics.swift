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

enum LyricTimingStatus: Hashable, Sendable {
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
            "Time cannot be negative."
        case .nonFinite:
            "Enter a valid time."
        case .exceedsTrackDuration:
            "Time exceeds the track duration."
        case .decreasing:
            "Time must not precede the previous lyric."
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
        guard timingStatus == .synchronized else {
            return nil
        }

        return lines.last { line in
            guard let startTime = line.startTime else {
                return false
            }
            return startTime <= time
        }
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
