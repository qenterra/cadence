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
            O_CREAT | O_RDWR | O_NOFOLLOW,
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
    private static let maximumPathCount = 256
    private static let maximumPathLength = 4096
    private static let notificationName = Notification.Name(
        "com.qenterra.cadence.open-files"
    )

    private let center: DistributedNotificationCenter
    private let authenticatorFactory: () -> (any CadenceInstanceMessageAuthenticating)?
    private var authenticator: (any CadenceInstanceMessageAuthenticating)?
    private var didLoadAuthenticator = false
    private var handler: (([URL]) -> Void)?
    private var isReceiving = false

    init(
        center: DistributedNotificationCenter = .default(),
        authenticator: (any CadenceInstanceMessageAuthenticating)? = nil,
        authenticatorFactory: @escaping () -> (any CadenceInstanceMessageAuthenticating)? = {
            try? CadenceInstanceMessageAuthenticator()
        }
    ) {
        self.center = center
        self.authenticator = authenticator
        self.authenticatorFactory = authenticatorFactory
        didLoadAuthenticator = authenticator != nil
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
        guard Self.isValid(paths: paths),
              let authenticator = resolvedAuthenticator()
        else {
            return
        }
        center.postNotificationName(
            Self.notificationName,
            object: nil,
            userInfo: [
                "paths": paths,
                "signature": authenticator.signature(for: paths),
            ],
            deliverImmediately: true
        )
    }

    @objc
    private func receiveOpenFiles(
        _ notification: Notification
    ) {
        guard let paths = notification.userInfo?["paths"] as? [String],
              let signature = notification.userInfo?["signature"] as? String,
              Self.isValid(paths: paths),
              let authenticator = resolvedAuthenticator(),
              authenticator.verifies(signature: signature, paths: paths)
        else {
            return
        }
        let urls = paths.map { URL(filePath: $0).standardizedFileURL }
        if !urls.isEmpty {
            handler?(urls)
        }
    }

    private static func isValid(paths: [String]) -> Bool {
        guard !paths.isEmpty,
              paths.count <= maximumPathCount
        else {
            return false
        }
        return paths.allSatisfy {
            $0.hasPrefix("/")
                && !$0.contains("\0")
                && $0.utf8.count <= maximumPathLength
        }
    }

    private func resolvedAuthenticator() ->
        (any CadenceInstanceMessageAuthenticating)? {
        guard !didLoadAuthenticator else {
            return authenticator
        }
        didLoadAuthenticator = true
        authenticator = authenticatorFactory()
        return authenticator
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
