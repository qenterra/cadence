import AppKit
import Darwin
import Foundation

enum CadenceMainScenePolicy {
    static let allowsMultipleWindows = false
}

enum CadenceInstanceClaim: Equatable, Sendable {
    case owner
    case duplicate
}

@MainActor
protocol CadenceInstanceLocking: AnyObject {
    func claim() -> Bool
}

@MainActor
protocol CadenceInstanceMessaging: AnyObject {
    func startReceiving(
        _ handler: @escaping ([URL]) -> Void
    )
    func send(urls: [URL])
}

@MainActor
protocol CadenceInstanceActivating: AnyObject {
    func activateOwner()
}

@MainActor
final class CadenceInstanceFileLock: CadenceInstanceLocking {
    private let lockURL: URL
    private var descriptor: Int32 = -1

    init(
        fileManager: FileManager = .default,
        bundleIdentifier: String = Bundle.main.bundleIdentifier
            ?? "com.qenterra.cadence"
    ) {
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let directory = support.appending(
            path: "Cadence/Instance",
            directoryHint: .isDirectory
        )
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        lockURL = directory.appending(
            path: "\(bundleIdentifier).lock",
            directoryHint: .notDirectory
        )
    }

    deinit {
        if descriptor >= 0 {
            _ = Darwin.close(descriptor)
        }
    }

    func claim() -> Bool {
        if descriptor >= 0 {
            return true
        }
        let opened = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard opened >= 0 else {
            return false
        }
        var advisoryLock = flock()
        advisoryLock.l_type = Int16(F_WRLCK)
        advisoryLock.l_whence = Int16(SEEK_SET)
        guard Darwin.fcntl(opened, F_SETLK, &advisoryLock) != -1 else {
            _ = Darwin.close(opened)
            return false
        }
        descriptor = opened
        return true
    }
}

@MainActor
final class DistributedCadenceInstanceMessaging: NSObject,
    CadenceInstanceMessaging {
    private static let notificationName = Notification.Name(
        "com.qenterra.cadence.open-files"
    )

    private let center: DistributedNotificationCenter
    private var handler: (([URL]) -> Void)?
    private var isReceiving = false

    init(center: DistributedNotificationCenter = .default()) {
        self.center = center
    }

    deinit {
        center.removeObserver(self)
    }

    func startReceiving(
        _ handler: @escaping ([URL]) -> Void
    ) {
        self.handler = handler
        guard !isReceiving else {
            return
        }
        isReceiving = true
        center.addObserver(
            self,
            selector: #selector(receiveOpenFiles(_:)),
            name: Self.notificationName,
            object: nil
        )
    }

    func send(urls: [URL]) {
        let paths = urls
            .filter(\.isFileURL)
            .map(\.standardizedFileURL.path)
        guard !paths.isEmpty else {
            return
        }
        center.postNotificationName(
            Self.notificationName,
            object: nil,
            userInfo: ["paths": paths],
            deliverImmediately: true
        )
    }

    @objc
    private func receiveOpenFiles(
        _ notification: Notification
    ) {
        guard let paths = notification.userInfo?["paths"] as? [String] else {
            return
        }
        let urls = paths.map { URL(filePath: $0).standardizedFileURL }
        if !urls.isEmpty {
            handler?(urls)
        }
    }
}

@MainActor
final class RunningCadenceApplicationActivator: CadenceInstanceActivating {
    private let bundleIdentifier: String

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier
            ?? "com.qenterra.cadence"
    ) {
        self.bundleIdentifier = bundleIdentifier
    }

    func activateOwner() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
        .first { $0.processIdentifier != currentPID }?
        .activate(options: [.activateAllWindows])
    }
}

@MainActor
final class CadenceInstanceCoordinator {
    static let shared = CadenceInstanceCoordinator()

    private let lock: any CadenceInstanceLocking
    private let messaging: any CadenceInstanceMessaging
    private let activator: any CadenceInstanceActivating
    private var currentClaim: CadenceInstanceClaim?
    private var handler: (([URL]) -> Void)?
    private var pendingOwnerBatches: [[URL]] = []

    init(
        lock: any CadenceInstanceLocking = CadenceInstanceFileLock(),
        messaging: any CadenceInstanceMessaging =
            DistributedCadenceInstanceMessaging(),
        activator: any CadenceInstanceActivating =
            RunningCadenceApplicationActivator()
    ) {
        self.lock = lock
        self.messaging = messaging
        self.activator = activator
    }

    func claim() -> CadenceInstanceClaim {
        if let currentClaim {
            return currentClaim
        }
        let claim: CadenceInstanceClaim = lock.claim() ? .owner : .duplicate
        currentClaim = claim
        return claim
    }

    func connect(
        _ handler: @escaping ([URL]) -> Void
    ) {
        guard claim() == .owner else {
            return
        }
        self.handler = handler
        messaging.startReceiving { [weak self] urls in
            self?.deliverToOwner(urls)
        }
        let pending = pendingOwnerBatches
        pendingOwnerBatches.removeAll()
        pending.forEach(handler)
    }

    func route(urls: [URL]) {
        let files = urls
            .filter(\.isFileURL)
            .map(\.standardizedFileURL)
        guard !files.isEmpty else {
            return
        }
        switch claim() {
        case .owner:
            deliverToOwner(files)
        case .duplicate:
            messaging.send(urls: files)
        }
    }

    func activateOwner() {
        if claim() == .duplicate {
            activator.activateOwner()
        }
    }

    private func deliverToOwner(
        _ urls: [URL]
    ) {
        if let handler {
            handler(urls)
        } else {
            pendingOwnerBatches.append(urls)
        }
    }
}
