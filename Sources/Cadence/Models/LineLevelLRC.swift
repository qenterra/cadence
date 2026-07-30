import Foundation

enum LineLevelLRC {
    enum Error: Swift.Error, Equatable {
        case malformedLine(Int)
        case incompleteTiming
        case emptyDocument
    }

    static func parse(
        _ source: String,
        trackID: LyricTrackIdentity
    ) throws -> LyricDocument {
        let result = try parseContent(source)
        return LyricDocument(
            trackID: trackID,
            lines: result.lines,
            metadataLines: result.metadataLines
        )
    }

    static func parse(
        _ source: String,
        trackID: TrackPreview.ID
    ) throws -> LyricDocument {
        try parse(source, trackID: .preview(trackID))
    }

    static func parse(
        _ source: String,
        trackID: UUID
    ) throws -> LyricDocument {
        try parse(source, trackID: .managed(trackID))
    }

    static func validate(_ source: String) throws {
        _ = try parseContent(source)
    }

    private struct ParsedContent {
        let lines: [LyricLine]
        let metadataLines: [String]
    }

    // swiftlint:disable:next function_body_length
    private static func parseContent(
        _ source: String
    ) throws -> ParsedContent {
        let timestampPattern = try NSRegularExpression(
            pattern: #"^\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
        )
        let metadataPattern = try NSRegularExpression(
            pattern: #"^\[[A-Za-z]+:.*\]$"#
        )
        let timestampLikePattern = try NSRegularExpression(
            pattern: #"^\[\d{1,3}:"#
        )

        let normalizedSource = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var sourceLines = normalizedSource.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        if normalizedSource.hasSuffix("\n"),
           sourceLines.last?.isEmpty == true {
            sourceLines.removeLast()
        }
        var lines: [LyricLine] = []
        var metadataLines: [String] = []

        for (index, substring) in sourceLines.enumerated() {
            let line = String(substring)
            if line.isEmpty {
                lines.append(LyricLine(text: ""))
                continue
            }

            let fullRange = NSRange(
                line.startIndex ..< line.endIndex,
                in: line
            )
            if metadataPattern.firstMatch(
                in: line,
                range: fullRange
            ) != nil {
                metadataLines.append(line)
                continue
            }

            var remainder = line
            var timestamps: [TimeInterval] = []
            while !remainder.isEmpty {
                let remainderRange = NSRange(
                    remainder.startIndex ..< remainder.endIndex,
                    in: remainder
                )
                guard
                    let match = timestampPattern.firstMatch(
                        in: remainder,
                        range: remainderRange
                    ),
                    match.range.location == 0
                else {
                    break
                }
                guard
                    let minutes = integerCapture(
                        1,
                        match: match,
                        source: remainder
                    ),
                    let seconds = integerCapture(
                        2,
                        match: match,
                        source: remainder
                    ),
                    seconds < 60,
                    let matchedRange = Range(
                        match.range,
                        in: remainder
                    )
                else {
                    throw Error.malformedLine(index + 1)
                }
                let fraction = fractionCapture(
                    3,
                    match: match,
                    source: remainder
                )
                timestamps.append(
                    TimeInterval(minutes * 60 + seconds) + fraction
                )
                remainder.removeSubrange(matchedRange)
            }

            if timestamps.isEmpty {
                if timestampLikePattern.firstMatch(
                    in: line,
                    range: fullRange
                ) != nil {
                    throw Error.malformedLine(index + 1)
                }
                lines.append(LyricLine(text: line))
            } else {
                lines.append(contentsOf: timestamps.map {
                    LyricLine(text: remainder, startTime: $0)
                })
            }
        }

        guard lines.contains(where: { !$0.isBlank }) else {
            throw Error.emptyDocument
        }
        return ParsedContent(
            lines: lines,
            metadataLines: metadataLines
        )
    }

    static func generate(_ document: LyricDocument) throws -> String {
        guard document.timingStatus != .missing else {
            throw Error.emptyDocument
        }

        let lyricLines = document.lines.map { line in
            if line.isBlank {
                return ""
            }
            if let startTime = line.startTime {
                return "[\(LyricTimestampFormatter.lrc(startTime))]\(line.text)"
            }
            return line.text
        }
        return (document.metadataLines + lyricLines)
            .joined(separator: "\n") + "\n"
    }

    private static func integerCapture(
        _ index: Int,
        match: NSTextCheckingResult,
        source: String
    ) -> Int? {
        guard
            let range = Range(match.range(at: index), in: source)
        else {
            return nil
        }
        return Int(source[range])
    }

    private static func fractionCapture(
        _ index: Int,
        match: NSTextCheckingResult,
        source: String
    ) -> TimeInterval {
        guard
            let range = Range(match.range(at: index), in: source)
        else {
            return 0
        }
        let digits = String(source[range])
        guard let value = Int(digits) else {
            return 0
        }
        return TimeInterval(value) / pow(10, Double(digits.count))
    }
}
