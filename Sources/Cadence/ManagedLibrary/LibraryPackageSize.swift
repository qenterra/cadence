import Foundation

enum LibraryPackageSize {
    static func formatted(at packageURL: URL?) async -> String {
        guard let packageURL else { return "—" }
        let byteCount = await Task.detached(priority: .utility) {
            allocatedByteCount(at: packageURL)
        }.value
        return ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }

    private static func allocatedByteCount(at root: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .isRegularFileKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return enumerator.reduce(into: Int64(0)) { total, element in
            guard let fileURL = element as? URL,
                  let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else {
                return
            }
            total += Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? 0
            )
        }
    }
}
