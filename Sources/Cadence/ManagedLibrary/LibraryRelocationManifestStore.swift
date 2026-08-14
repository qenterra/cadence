import Foundation

struct LibraryRelocationManifestStore: Sendable {
    typealias Writer = @Sendable (LibraryRelocationManifest, URL) throws -> Void

    let write: Writer

    static let live = LibraryRelocationManifestStore { manifest, url in
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }
}
