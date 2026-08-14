import AppKit
@testable import Cadence
import Foundation
import Testing

@MainActor
struct CadenceApplicationDelegateTests {
    @Test("AppKit delivers one ordered URL batch for document events")
    func documentEventSelector() {
        let delegate = CadenceApplicationDelegate()

        #expect(
            delegate.responds(
                to: NSSelectorFromString("application:openURLs:")
            )
        )
        #expect(
            !delegate.responds(
                to: NSSelectorFromString("application:openFiles:")
            )
        )
    }

    @Test("Startup open batches are buffered and preserve Finder order")
    func startupBuffering() {
        let delegate = CadenceApplicationDelegate()
        let first = URL(filePath: "/tmp/First.flac")
        let second = URL(filePath: "/tmp/Second.mp3")
        var batches: [[URL]] = []

        delegate.application(.shared, open: [second, first])
        delegate.connect { batches.append($0) }

        #expect(batches == [[second, first]])
    }

    @Test("An empty open callback is ignored")
    func emptyBatch() {
        let delegate = CadenceApplicationDelegate()
        var batches: [[URL]] = []
        delegate.connect { batches.append($0) }

        delegate.application(.shared, open: [])

        #expect(batches.isEmpty)
    }
}
