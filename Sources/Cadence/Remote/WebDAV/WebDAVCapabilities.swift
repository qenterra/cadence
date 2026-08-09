import Foundation

struct WebDAVCapabilities: Equatable, Sendable {
    let supportsClass1: Bool
    let supportsClass2: Bool
    let supportsByteRanges: Bool
}
