import Foundation

enum LineLevelLRC {
    enum Error: Swift.Error, Equatable {
        case malformedLine(Int)
        case incompleteTiming
        case emptyDocument
    }

    static func parse(
        _ source: String,
        trackID: TrackPreview.ID
    ) throws -> LyricDocument {
        let lines = try parseLines(source)
        return LyricDocument(trackID: trackID, lines: lines)
    }

    static func validate(_ source: String) throws {
        _ = try parseLines(source)
    }

    // swiftlint:disable:next function_body_length
    private static func parseLines(
        _ source: String
    ) throws -> [LyricLine] {
        let timestampPattern = try NSRegularExpression(
            pattern: #"^\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\](.*)$"#
        )
        let metadataPattern = try NSRegularExpression(
            pattern: #"^\[[A-Za-z]+:.*\]$"#
        )

        let sourceLines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        var lines: [LyricLine] = []

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
                continue
            }

            guard
                let match = timestampPattern.firstMatch(
                    in: line,
                    range: fullRange
                ),
                let minutes = integerCapture(1, match: match, source: line),
                let seconds = integerCapture(2, match: match, source: line),
                seconds < 60,
                let textRange = Range(match.range(at: 4), in: line)
            else {
                throw Error.malformedLine(index + 1)
            }

            let fraction = fractionCapture(3, match: match, source: line)
            let time = TimeInterval(minutes * 60 + seconds) + fraction
            lines.append(
                LyricLine(
                    text: String(line[textRange]),
                    startTime: time
                )
            )
        }

        guard lines.contains(where: { $0.startTime != nil }) else {
            throw Error.emptyDocument
        }
        return lines
    }

    static func generate(_ document: LyricDocument) throws -> String {
        guard document.timingStatus != .missing else {
            throw Error.emptyDocument
        }
        guard document.timingStatus == .synchronized else {
            throw Error.incompleteTiming
        }

        return try document.lines.map { line in
            if line.isBlank {
                return ""
            }
            guard let startTime = line.startTime else {
                throw Error.incompleteTiming
            }
            return "[\(LyricTimestampFormatter.lrc(startTime))]\(line.text)"
        }
        .joined(separator: "\n")
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
