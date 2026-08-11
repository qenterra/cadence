import Foundation

struct RhythmFocusLyricProjection: Sendable {
    static let slotCount = 5
    static let activeSlotIndex = 2

    let slots: [LyricLine?]
    let activeLineID: LyricLine.ID?
    let status: LyricTimingStatus

    static func make(
        document: LyricDocument?,
        presentationTime: TimeInterval
    ) -> RhythmFocusLyricProjection {
        guard let document else {
            return unavailable(status: .missing)
        }
        guard document.timingStatus == .synchronized else {
            return unavailable(status: document.timingStatus)
        }

        let contentLines = document.lines.filter { !$0.isBlank }
        guard !contentLines.isEmpty else {
            return unavailable(status: .missing)
        }
        let activeLine = document.activeLine(at: presentationTime)
        let anchorIndex = activeLine.flatMap { activeLine in
            contentLines.firstIndex { $0.id == activeLine.id }
        } ?? 0
        let slots = (-Self.activeSlotIndex ... Self.activeSlotIndex).map { offset -> LyricLine? in
            let index = anchorIndex + offset
            guard contentLines.indices.contains(index) else {
                return nil
            }
            return contentLines[index]
        }

        return RhythmFocusLyricProjection(
            slots: slots,
            activeLineID: activeLine?.id,
            status: .synchronized
        )
    }

    private static func unavailable(
        status: LyricTimingStatus
    ) -> RhythmFocusLyricProjection {
        RhythmFocusLyricProjection(
            slots: Array(repeating: nil, count: slotCount),
            activeLineID: nil,
            status: status
        )
    }
}
