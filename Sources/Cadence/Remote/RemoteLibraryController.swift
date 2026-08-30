import AppKit
import Foundation
import Observation

enum RemoteLibraryStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case ready(provider: String, trackCount: Int)
    case unavailable(String)
}

enum RemoteLibraryIdentityExpectation: Equatable, Sendable {
    case unbound
    case exact(UUID)
    case unavailable(String)
}

enum RemoteProviderConfiguration: Codable, Equatable, Sendable {
    case webDAV(rootURL: URL, username: String, credentialKey: String)
    case googleDrive(
        drive: GoogleDriveConfiguration,
        clientID: String,
        redirectURL: URL
    )

    var displayName: String {
        switch self {
        case .webDAV: "WebDAV"
        case .googleDrive: "Google Drive"
        }
    }
}

struct RemoteLibrarySettingsRecord: Codable, Equatable, Sendable {
    var provider: RemoteProviderConfiguration
    var cacheBudgetBytes: Int64
}

/// Persists remote-provider configuration, never credentials or access tokens.
///
/// Credential material belongs in the provider-specific Keychain store. A
/// corrupt settings record throws and becomes an explicit unavailable state.
@MainActor
protocol RemoteLibrarySettingsStoring: AnyObject {
    func load() throws -> RemoteLibrarySettingsRecord?
    func save(_ record: RemoteLibrarySettingsRecord?) throws
}

@MainActor
final class UserDefaultsRemoteLibrarySettingsStore: RemoteLibrarySettingsStoring {
    private static let key = "remoteLibrary.settings.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws -> RemoteLibrarySettingsRecord? {
        guard let data = defaults.data(forKey: Self.key) else {
            return nil
        }
        return try JSONDecoder().decode(
            RemoteLibrarySettingsRecord.self,
            from: data
        )
    }

    func save(_ record: RemoteLibrarySettingsRecord?) throws {
        guard let record else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        let data = try JSONEncoder().encode(record)
        defaults.set(data, forKey: Self.key)
    }
}

@MainActor
@Observable
final class RemoteLibraryController {
    static let defaultCacheBudgetBytes: Int64 = 10 * 1024 * 1024 * 1024

    private(set) var status: RemoteLibraryStatus = .disconnected
    private(set) var configuredProviderName: String?
    var cacheBudgetBytes: Int64
    private(set) var isClearingCache = false
    private(set) var cacheClearResult: RemoteCacheClearResult?
    private(set) var cacheClearError: String?

    @ObservationIgnored private let source: RemotePlaybackSource
    @ObservationIgnored private let store: any RemoteLibrarySettingsStoring
    @ObservationIgnored private let identityExpectation: RemoteLibraryIdentityExpectation
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let webDAVAuthenticationFactory: @Sendable (String) -> WebDAVAuthentication
    @ObservationIgnored private let webDAVProviderFactory: @Sendable (
        URL,
        WebDAVAuthentication
    ) -> any WebDAVRemoteLibraryProvider
    @ObservationIgnored private var webDAVAuthentication: WebDAVAuthentication?
    @ObservationIgnored private var googleDriveProvider: GoogleDriveProvider?

    init(
        source: RemotePlaybackSource,
        identityExpectation: RemoteLibraryIdentityExpectation,
        store: any RemoteLibrarySettingsStoring = UserDefaultsRemoteLibrarySettingsStore(),
        fileManager: FileManager = .default,
        webDAVAuthenticationFactory: @escaping @Sendable (String) -> WebDAVAuthentication = {
            WebDAVAuthentication(key: $0)
        },
        webDAVProviderFactory: @escaping @Sendable (
            URL,
            WebDAVAuthentication
        ) -> any WebDAVRemoteLibraryProvider = { rootURL, authentication in
            WebDAVProvider(rootURL: rootURL, authentication: authentication)
        }
    ) {
        self.source = source
        self.identityExpectation = identityExpectation
        self.store = store
        self.fileManager = fileManager
        self.webDAVAuthenticationFactory = webDAVAuthenticationFactory
        self.webDAVProviderFactory = webDAVProviderFactory
        cacheBudgetBytes = Self.defaultCacheBudgetBytes
        configuredProviderName = nil
    }

    func restore() async {
        if case let .unavailable(message) = identityExpectation {
            status = .unavailable(message)
            return
        }
        status = .connecting
        do {
            guard let record = try store.load() else {
                status = .disconnected
                return
            }
            cacheBudgetBytes = record.cacheBudgetBytes
            configuredProviderName = record.provider.displayName
            switch record.provider {
            case let .webDAV(rootURL, _, credentialKey):
                try Self.validateRemoteURL(rootURL)
                let authentication = webDAVAuthenticationFactory(credentialKey)
                try await authentication.restore()
                let provider = webDAVProviderFactory(rootURL, authentication)
                try await activate(
                    provider: provider,
                    name: record.provider.displayName
                )
                webDAVAuthentication = authentication
            case let .googleDrive(drive, _, _):
                let authentication = AppAuthGoogleDriveAuthentication()
                try await authentication.restoreSession()
                let provider = GoogleDriveProvider(
                    configuration: drive,
                    authorization: authentication
                )
                try await activate(
                    provider: provider,
                    name: record.provider.displayName
                )
                googleDriveProvider = provider
            }
        } catch {
            await source.deactivate()
            status = .unavailable(error.localizedDescription)
        }
    }

    func connectWebDAV(
        rootURL: URL,
        username: String,
        password: String
    ) async {
        status = .connecting
        var pendingAuthentication: WebDAVAuthentication?
        do {
            try Self.validateRemoteURL(rootURL)
            let credentialKey = "\(rootURL.absoluteString)|\(username)"
            let authentication = webDAVAuthenticationFactory(credentialKey)
            pendingAuthentication = authentication
            try await authentication.signIn(
                WebDAVCredentials(username: username, password: password)
            )
            let provider = webDAVProviderFactory(rootURL, authentication)
            let capabilities = try await provider.capabilities()
            guard capabilities.supportsClass1 else {
                throw RemoteProviderError.serviceUnavailable(
                    "This server does not advertise WebDAV Class 1 support."
                )
            }
            try await activate(provider: provider, name: "WebDAV")
            try store.save(RemoteLibrarySettingsRecord(
                provider: .webDAV(
                    rootURL: rootURL,
                    username: username,
                    credentialKey: credentialKey
                ),
                cacheBudgetBytes: cacheBudgetBytes
            ))
            try await googleDriveProvider?.signOut()
            webDAVAuthentication = authentication
            pendingAuthentication = nil
            googleDriveProvider = nil
            configuredProviderName = "WebDAV"
        } catch {
            try? await pendingAuthentication?.signOut()
            await source.deactivate()
            status = .unavailable(error.localizedDescription)
        }
    }

    func connectGoogleDrive(
        drive: GoogleDriveConfiguration,
        clientID: String,
        redirectURL: URL,
        presentingWindow: NSWindow
    ) async {
        status = .connecting
        var pendingProvider: GoogleDriveProvider?
        do {
            let authentication = AppAuthGoogleDriveAuthentication()
            try await authentication.authorize(
                clientID: clientID,
                redirectURL: redirectURL,
                presentingWindow: presentingWindow
            )
            let provider = GoogleDriveProvider(
                configuration: drive,
                authorization: authentication
            )
            pendingProvider = provider
            try await activate(provider: provider, name: "Google Drive")
            try store.save(RemoteLibrarySettingsRecord(
                provider: .googleDrive(
                    drive: drive,
                    clientID: clientID,
                    redirectURL: redirectURL
                ),
                cacheBudgetBytes: cacheBudgetBytes
            ))
            try await webDAVAuthentication?.signOut()
            googleDriveProvider = provider
            pendingProvider = nil
            webDAVAuthentication = nil
            configuredProviderName = "Google Drive"
        } catch {
            try? await pendingProvider?.signOut()
            await source.deactivate()
            status = .unavailable(error.localizedDescription)
        }
    }

    func disconnect() async {
        do {
            try await webDAVAuthentication?.signOut()
            try await googleDriveProvider?.signOut()
            try store.save(nil)
        } catch {
            status = .unavailable(error.localizedDescription)
            return
        }
        webDAVAuthentication = nil
        googleDriveProvider = nil
        configuredProviderName = nil
        status = .disconnected
        await source.deactivate()
    }

    func setCacheBudget(
        _ bytes: Int64
    ) async {
        let previousBudget = cacheBudgetBytes
        let updatedBudget = max(bytes, 0)
        let hasActiveCache = if case .ready = status {
            true
        } else {
            false
        }
        do {
            if hasActiveCache {
                try await source.setCacheBudget(updatedBudget)
            }
            if var record = try store.load() {
                record.cacheBudgetBytes = updatedBudget
                try store.save(record)
            }
            cacheBudgetBytes = updatedBudget
        } catch {
            if hasActiveCache {
                do {
                    try await source.setCacheBudget(previousBudget)
                } catch let rollbackError {
                    status = .unavailable(
                        "\(error.localizedDescription) Rollback also failed: \(rollbackError.localizedDescription)"
                    )
                    return
                }
            }
            status = .unavailable(error.localizedDescription)
        }
    }

    func clearCache() async {
        guard !isClearingCache else {
            return
        }
        isClearingCache = true
        cacheClearResult = nil
        cacheClearError = nil
        defer { isClearingCache = false }
        do {
            cacheClearResult = try await source.clearCache()
        } catch {
            cacheClearError = error.localizedDescription
        }
    }
}

private extension RemoteLibraryController {
    func activate(
        provider: any RemoteLibraryProvider,
        name: String
    ) async throws {
        if case let .unavailable(message) = identityExpectation {
            throw RemoteProviderError.serviceUnavailable(message)
        }
        let response = try await provider.fetchManifest(ifNoneMatch: nil)
        guard let manifest = response.manifest else {
            throw RemoteProviderError.invalidManifest("missing initial manifest")
        }
        if case let .exact(expectedLibraryID) = identityExpectation,
           manifest.libraryID != expectedLibraryID {
            throw RemoteProviderError.conflict
        }
        let cacheRoot = try cacheRootURL(libraryID: manifest.libraryID)
        try await source.activate(
            provider: provider,
            manifest: manifest,
            cacheRootURL: cacheRoot,
            budgetBytes: cacheBudgetBytes
        )
        status = .ready(provider: name, trackCount: manifest.tracks.count)
    }

    func cacheRootURL(
        libraryID: UUID
    ) throws -> URL {
        guard let caches = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw RemoteProviderError.serviceUnavailable(
                "The local cache directory is unavailable."
            )
        }
        return caches
            .appending(path: "com.qenterra.cadence", directoryHint: .isDirectory)
            .appending(path: "RemoteMedia", directoryHint: .isDirectory)
            .appending(path: libraryID.uuidString, directoryHint: .isDirectory)
    }

    static func validateRemoteURL(
        _ url: URL
    ) throws {
        let isSecure = url.scheme?.lowercased() == "https"
        let isLocalHTTP = url.scheme?.lowercased() == "http"
            && ["localhost", "127.0.0.1", "::1"].contains(
                url.host?.lowercased() ?? ""
            )
        guard isSecure || isLocalHTTP else {
            throw RemoteProviderError.serviceUnavailable(
                "Use HTTPS for remote WebDAV servers."
            )
        }
    }
}
