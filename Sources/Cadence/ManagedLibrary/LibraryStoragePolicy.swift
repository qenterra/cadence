import Foundation

enum LibraryStorageMode: String, CaseIterable, Identifiable, Sendable {
    case optimize
    case downloadOriginals

    static let defaultsKey = "library.storage.mode"

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .optimize:
            String(localized: "Optimize Mac Storage")
        case .downloadOriginals:
            String(localized: "Download Originals to This Mac")
        }
    }
}

struct LibraryStoragePolicy: Equatable, Sendable {
    let mode: LibraryStorageMode

    var downloadsOriginalsEagerly: Bool {
        mode == .downloadOriginals
    }

    var permitsEviction: Bool {
        mode == .optimize
    }
}

struct LibraryStoragePolicyApplier: Sendable {
    func apply(
        _ policy: LibraryStoragePolicy,
        to package: ManagedLibraryPackage,
        fileManager: FileManager = .default
    ) throws {
        guard policy.downloadsOriginalsEagerly else {
            return
        }
        for url in mediaFiles(in: package, fileManager: fileManager) where
            fileManager.isUbiquitousItem(at: url) {
            try fileManager.startDownloadingUbiquitousItem(at: url)
        }
    }

    func evictDownloadedOriginals(
        in package: ManagedLibraryPackage,
        fileManager: FileManager = .default
    ) throws {
        for url in mediaFiles(in: package, fileManager: fileManager) where
            fileManager.isUbiquitousItem(at: url) {
            try fileManager.evictUbiquitousItem(at: url)
        }
    }

    private func mediaFiles(
        in package: ManagedLibraryPackage,
        fileManager: FileManager
    ) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: package.mediaDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(
                      forKeys: [.isRegularFileKey]
                  ).isRegularFile) == true
            else {
                return nil
            }
            return url
        }
    }
}
