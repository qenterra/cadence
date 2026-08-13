@testable import Cadence
import Foundation

final class TrashMoveFailureScript: @unchecked Sendable {
    private let lock = NSLock()
    private var forwardMoveCount = 0

    var client: TrashFileClient {
        TrashFileClient(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            createDirectory: {
                try FileManager.default.createDirectory(
                    at: $0,
                    withIntermediateDirectories: true
                )
            },
            moveItem: { [self] source, destination in
                lock.lock()
                defer { lock.unlock() }
                if source.path.contains("/Trash/") {
                    throw InjectedTrashFailure("injected rollback failure")
                }
                forwardMoveCount += 1
                if forwardMoveCount == 2 {
                    throw InjectedTrashFailure("injected move failure")
                }
                try FileManager.default.moveItem(
                    at: source,
                    to: destination
                )
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )
    }
}

private struct InjectedTrashFailure: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

extension TrashFileClient {
    static let directoryCreationFailure = TrashFileClient(
        fileExists: live.fileExists,
        createDirectory: { _ in
            throw InjectedTrashFailure(
                "injected directory creation failure"
            )
        },
        moveItem: live.moveItem,
        removeItem: { _ in
            throw InjectedTrashFailure("retain recovery evidence")
        }
    )

    static let cleanupFailure = TrashFileClient(
        fileExists: live.fileExists,
        createDirectory: live.createDirectory,
        moveItem: live.moveItem,
        removeItem: { _ in
            throw InjectedTrashFailure("injected cleanup failure")
        }
    )

    static let restoreRollbackFailure = TrashFileClient(
        fileExists: live.fileExists,
        createDirectory: live.createDirectory,
        moveItem: { source, destination in
            if !source.path.contains("/Trash/"),
               destination.path.contains("/Trash/") {
                throw InjectedTrashFailure(
                    "injected restore rollback failure"
                )
            }
            try FileManager.default.moveItem(at: source, to: destination)
        },
        removeItem: live.removeItem
    )
}

extension URL {
    var isPresent: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
