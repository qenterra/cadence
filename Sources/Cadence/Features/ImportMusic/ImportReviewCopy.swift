import Foundation

enum ImportReviewCopy {
    static func selectionSummary(count: Int, size: String) -> String {
        let noun = count == 1
            ? String(localized: "track selected")
            : String(localized: "tracks selected")
        return "\(count.formatted()) \(noun) · \(size)"
    }

    static func importAction(count: Int) -> String {
        let noun = count == 1
            ? String(localized: "Track")
            : String(localized: "Tracks")
        return "\(String(localized: "Import")) \(count.formatted()) \(noun)"
    }
}
