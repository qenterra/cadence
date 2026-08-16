import Foundation

@MainActor
protocol MediaMaterializing {
    func materialize(_ url: URL) async throws
}

struct UbiquitousMediaMaterializer: MediaMaterializing {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func materialize(_ url: URL) async throws {
        guard fileManager.isUbiquitousItem(at: url) else {
            return
        }
        try fileManager.startDownloadingUbiquitousItem(at: url)
        while try !isDownloaded(url) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func isDownloaded(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(
            forKeys: [.ubiquitousItemDownloadingStatusKey]
        )
        switch values.ubiquitousItemDownloadingStatus {
        case .current, .downloaded:
            return true
        default:
            return false
        }
    }
}
