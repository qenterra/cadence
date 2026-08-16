import CloudKit
import Foundation
import Observation
import Security

enum CloudKitRuntimeAvailability {
    static let serviceEntitlement = "com.apple.developer.icloud-services"
    static let containerEntitlement = "com.apple.developer.icloud-container-identifiers"

    static func isAvailable(
        _ readEntitlement: (String) -> Any?
    ) -> Bool {
        guard let services = readEntitlement(serviceEntitlement) as? [String],
              services.contains("CloudKit"),
              let containers = readEntitlement(containerEntitlement) as? [String]
        else {
            return false
        }
        return containers.contains(CloudKitLibrarySyncEngine.containerIdentifier)
    }

    static func makeContainer() -> CKContainer? {
        guard isAvailable(currentProcessEntitlement) else {
            return nil
        }
        return CKContainer(
            identifier: CloudKitLibrarySyncEngine.containerIdentifier
        )
    }

    private static func currentProcessEntitlement(
        _ key: String
    ) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return nil
        }
        return SecTaskCopyValueForEntitlement(
            task,
            key as CFString,
            nil
        )
    }
}

enum LibraryCloudSyncStatus: Equatable, Sendable {
    case unavailable(String)
    case idle
    case syncing
    case synced(Date)
    case failed(String)
}

@MainActor
@Observable
final class LibraryCloudSyncController {
    private(set) var status: LibraryCloudSyncStatus = .idle
    private let engine: CloudKitLibrarySyncEngine
    private let repository: LibraryRepository
    private let mediaSource: CloudMediaPlaybackSource
    private let identity: LibraryIdentity
    private let identityStore: CloudLibraryIdentityStore
    private var periodicTask: Task<Void, Never>?

    init(
        engine: CloudKitLibrarySyncEngine,
        repository: LibraryRepository,
        mediaSource: CloudMediaPlaybackSource,
        identity: LibraryIdentity,
        identityStore: CloudLibraryIdentityStore
    ) {
        self.engine = engine
        self.repository = repository
        self.mediaSource = mediaSource
        self.identity = identity
        self.identityStore = identityStore
    }

    func start() {
        guard periodicTask == nil else {
            return
        }
        periodicTask = Task { [weak self] in
            guard let self else { return }
            await synchronize()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await synchronize()
            }
        }
    }

    func stop() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    func synchronize() async {
        status = .syncing
        do {
            let account = try await engine.accountStatus()
            guard account == .available else {
                status = .unavailable(Self.message(for: account))
                return
            }
            try await identityStore.register(identity)
            try await engine.synchronize(repository: repository)
            try await mediaSource.synchronizeAssets()
            status = .synced(.now)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func downloadAllOriginals() async throws {
        try await mediaSource.downloadAllOriginals()
    }

    private static func message(
        for status: CKAccountStatus
    ) -> String {
        switch status {
        case .available:
            "iCloud is available."
        case .noAccount:
            "Sign in to iCloud to sync this library."
        case .restricted:
            "iCloud access is restricted on this Mac."
        case .couldNotDetermine:
            "Cadence could not determine the current iCloud account."
        case .temporarilyUnavailable:
            "iCloud is temporarily unavailable."
        @unknown default:
            "iCloud is unavailable."
        }
    }
}

struct LibraryCloudRuntime {
    let controller: LibraryCloudSyncController
    let mediaSource: CloudMediaPlaybackSource
}

enum LibraryCloudSyncFactory {
    @MainActor
    static func make(
        librarySession: LibrarySession,
        containerProvider: () -> CKContainer? = CloudKitRuntimeAvailability.makeContainer
    ) -> LibraryCloudRuntime? {
        guard !CadenceLaunchEnvironment.shouldUsePreviewLibrary(),
              let location = librarySession.location,
              let repository = librarySession.store.repository,
              let identity = try? ManagedLibraryPackage(
                  location: location
              ).readIdentity(),
              let replica = try? LocalLibraryReplicaLocation.currentUser(
                  identity: identity
              ),
              let container = containerProvider() else {
            return nil
        }
        let deviceID = DeviceIdentity.current()
        let engine = CloudKitLibrarySyncEngine(
            libraryID: identity.id,
            deviceID: deviceID,
            stateURL: replica.rootURL.appending(
                path: "Sync/CloudKit.json",
                directoryHint: .notDirectory
            ),
            container: container
        ) { records in
            try await repository.applyCloudRecords(records)
            await librarySession.store.loadInitialLibrary()
        }
        let package = ManagedLibraryPackage(location: location)
        let assetStore = CloudMediaAssetStore(
            libraryID: identity.id,
            package: package,
            stagingDirectory: replica.rootURL.appending(
                path: "Sync/Media",
                directoryHint: .isDirectory
            ),
            container: container
        )
        let mediaSource = CloudMediaPlaybackSource(
            repository: repository,
            package: package,
            assetStore: assetStore
        )
        let controller = LibraryCloudSyncController(
            engine: engine,
            repository: repository,
            mediaSource: mediaSource,
            identity: identity,
            identityStore: CloudLibraryIdentityStore(
                container: container
            )
        )
        return LibraryCloudRuntime(
            controller: controller,
            mediaSource: mediaSource
        )
    }
}

private enum DeviceIdentity {
    static let key = "cloudSync.deviceID"

    static func current(
        defaults: UserDefaults = .standard
    ) -> UUID {
        if let rawValue = defaults.string(forKey: key),
           let id = UUID(uuidString: rawValue) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}
