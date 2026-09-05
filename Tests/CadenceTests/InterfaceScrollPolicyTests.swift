@testable import Cadence
import Foundation
import Testing

struct InterfaceScrollPolicyTests {
    @Test("Page-owned track lists expand to every row")
    func pageOwnedTrackListHeight() {
        #expect(
            TrackListLayout.contentHeight(
                rowCount: 4,
                showsHeader: true
            ) == 270
        )
        #expect(
            TrackListLayout.contentHeight(
                rowCount: 0,
                showsHeader: true
            ) == 38
        )
        #expect(
            TrackListLayout.contentHeight(
                rowCount: -4,
                showsHeader: false
            ) == 0
        )
    }

    @Test("Contained and page-owned lists remain distinct policies")
    func trackListScrollOwnership() {
        #expect(TrackListScrollOwnership.contained != .page)
    }

    @Test("Interface scroll containers never enable horizontal scrolling")
    func verticalScrollPolicy() throws {
        let sourceRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/Cadence", directoryHint: .isDirectory)
        let files = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        )
        let horizontalSwiftUIScroll = #"ScrollView\s*\([^)]*\.horizontal"#
        let implicitSwiftUIScroll = #"(?m)^\s*ScrollView\s*\{"#
        var violations: [String] = []

        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift" else {
                continue
            }
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.range(
                of: horizontalSwiftUIScroll,
                options: .regularExpression
            ) != nil || source.range(
                of: implicitSwiftUIScroll,
                options: .regularExpression
            ) != nil || source.contains("hasHorizontalScroller = true") {
                violations.append(file.path)
            }
        }

        #expect(violations.isEmpty)
    }
}
