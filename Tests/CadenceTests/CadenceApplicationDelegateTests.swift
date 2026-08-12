@testable import Cadence
import Foundation
import Testing

@MainActor
struct CadenceApplicationDelegateTests {
    @Test("Startup open batches are buffered and preserve URL order")
    func startupBuffering() {
        let delegate = CadenceApplicationDelegate()
        let first = URL(filePath: "/tmp/First.flac")
        let second = URL(filePath: "/tmp/Second.mp3")
        var batches: [[URL]] = []

        delegate.receiveOpenURLs([second, first])
        delegate.connect { batches.append($0) }
        delegate.receiveOpenURLs([first])

        #expect(batches == [[second, first], [first]])
    }

    @Test("An empty open callback is ignored")
    func emptyBatch() {
        let delegate = CadenceApplicationDelegate()
        var batches: [[URL]] = []
        delegate.connect { batches.append($0) }

        delegate.receiveOpenURLs([])

        #expect(batches.isEmpty)
    }
}
