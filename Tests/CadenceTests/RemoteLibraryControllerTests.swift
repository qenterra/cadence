@testable import Cadence
import Foundation
import Testing

@MainActor
struct RemoteLibraryControllerTests {
    @Test("A failed WebDAV setup removes newly stored credentials")
    func failedWebDAVSetupDeletesNewCredentials() async throws {
        let credentials = ControllerCredentialStore()
        let settings = ControllerSettingsStore()
        let provider = WebDAVActivationFailureProvider()
        let rootURL = try #require(
            URL(string: "https://dav.example.test/Cadence/")
        )
        let credentialKey = "\(rootURL.absoluteString)|nikita"
        let controller = RemoteLibraryController(
            source: RemotePlaybackSource(),
            identityExpectation: .unbound,
            store: settings,
            webDAVAuthenticationFactory: { key in
                WebDAVAuthentication(key: key, store: credentials)
            },
            webDAVProviderFactory: { _, _ in provider }
        )

        await controller.connectWebDAV(
            rootURL: rootURL,
            username: "nikita",
            password: "secret"
        )

        #expect(try await credentials.load(key: credentialKey) == nil)
        #expect(settings.record == nil)
        guard case .unavailable = controller.status else {
            Issue.record("Expected failed setup to be unavailable.")
            return
        }
    }
}

@MainActor
private final class ControllerSettingsStore: RemoteLibrarySettingsStoring {
    var record: RemoteLibrarySettingsRecord?

    func load() throws -> RemoteLibrarySettingsRecord? {
        record
    }

    func save(_ record: RemoteLibrarySettingsRecord?) throws {
        self.record = record
    }
}

private actor ControllerCredentialStore: WebDAVCredentialStoring {
    private var values: [String: WebDAVCredentials] = [:]

    func load(key: String) async throws -> WebDAVCredentials? {
        values[key]
    }

    func save(_ credentials: WebDAVCredentials, key: String) async throws {
        values[key] = credentials
    }

    func delete(key: String) async throws {
        values[key] = nil
    }
}

private actor WebDAVActivationFailureProvider: WebDAVRemoteLibraryProvider {
    func capabilities() async throws -> WebDAVCapabilities {
        WebDAVCapabilities(
            supportsClass1: false,
            supportsClass2: false,
            supportsByteRanges: false
        )
    }

    // periphery:ignore - Required by the full provider protocol for this capability-only fake.
    func restoreSession() async throws {}

    func fetchManifest(ifNoneMatch _: String?) async throws -> RemoteManifestResponse {
        throw RemoteProviderError.serviceUnavailable("unused")
    }

    func read(
        object _: RemoteObjectID,
        range _: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        throw RemoteProviderError.serviceUnavailable("unused")
    }

    // periphery:ignore - Required by the full provider protocol for this capability-only fake.
    func uploadTemporary(
        object _: RemoteObjectID,
        bytes _: AsyncThrowingStream<Data, Error>
    ) async throws -> RemoteUpload {
        throw RemoteProviderError.serviceUnavailable("unused")
    }

    // periphery:ignore - Required by the full provider protocol for this capability-only fake.
    func finalize(_: RemoteUpload, expectedSHA256 _: String) async throws {}

    // periphery:ignore - Required by the full provider protocol for this capability-only fake.
    func commitManifest(
        _: RemoteLibraryManifest,
        matching _: String?
    ) async throws -> String {
        throw RemoteProviderError.serviceUnavailable("unused")
    }

    // periphery:ignore - Required by the full provider protocol for this capability-only fake.
    func delete(object _: RemoteObjectID) async throws {}
}
