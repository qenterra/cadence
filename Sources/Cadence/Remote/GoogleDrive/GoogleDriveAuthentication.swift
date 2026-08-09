@preconcurrency import AppAuth
import AppKit
import Foundation
import Security

protocol GoogleDriveAuthorizing: Sendable {
    func restoreSession() async throws
    func accessToken() async throws -> String
    func signOut() async throws
}

protocol OAuthStateStoring: Sendable {
    func load(key: String) async throws -> Data?
    func save(
        _ data: Data,
        key: String
    ) async throws
    func delete(key: String) async throws
}

actor KeychainOAuthStateStore: OAuthStateStoring {
    private let service: String

    init(service: String = "com.qenterra.cadence.oauth") {
        self.service = service
    }

    func load(
        key: String
    ) async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data
        else {
            throw RemoteProviderError.authenticationRequired
        }
        return data
    }

    func save(
        _ data: Data,
        key: String
    ) async throws {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = identity
            attributes.forEach { insertion[$0.key] = $0.value }
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
                throw RemoteProviderError.authenticationRequired
            }
        } else if status != errSecSuccess {
            throw RemoteProviderError.authenticationRequired
        }
    }

    func delete(
        key: String
    ) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RemoteProviderError.authenticationRequired
        }
    }
}

@MainActor
final class AppAuthGoogleDriveAuthentication: GoogleDriveAuthorizing {
    private typealias AuthContinuation = CheckedContinuation<OIDAuthState, Error>
    private typealias TokenContinuation = CheckedContinuation<String, Error>
    private static let authorizationEndpoint = URL(
        string: "https://accounts.google.com/o/oauth2/v2/auth"
    )!
    private static let tokenEndpoint = URL(
        string: "https://oauth2.googleapis.com/token"
    )!
    private static let driveScope = "https://www.googleapis.com/auth/drive.file"

    private let key: String
    private let store: any OAuthStateStoring
    private var state: OIDAuthState?
    private var authorizationFlow: (any OIDExternalUserAgentSession)?

    init(
        key: String = "google-drive",
        store: any OAuthStateStoring = KeychainOAuthStateStore()
    ) {
        self.key = key
        self.store = store
    }

    func restoreSession() async throws {
        guard let data = try await store.load(key: key),
              let restored = try NSKeyedUnarchiver.unarchivedObject(
                  ofClass: OIDAuthState.self,
                  from: data
              )
        else {
            throw RemoteProviderError.authenticationRequired
        }
        state = restored
    }

    func authorize(
        clientID: String,
        redirectURL: URL,
        presentingWindow: NSWindow
    ) async throws {
        guard !clientID.isEmpty else {
            throw RemoteProviderError.authenticationRequired
        }
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: Self.authorizationEndpoint,
            tokenEndpoint: Self.tokenEndpoint
        )
        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: clientID,
            clientSecret: nil,
            scopes: [OIDScopeOpenID, Self.driveScope],
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: [
                "access_type": "offline",
                "prompt": "consent",
            ]
        )
        let authorized = try await withCheckedThrowingContinuation { (continuation: AuthContinuation) in
            authorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                presenting: presentingWindow
            ) { state, error in
                if let state {
                    continuation.resume(returning: state)
                } else {
                    continuation.resume(
                        throwing: error ?? RemoteProviderError.authenticationRequired
                    )
                }
            }
        }
        state = authorized
        authorizationFlow = nil
        try await persist(authorized)
    }

    func accessToken() async throws -> String {
        guard let state else {
            throw RemoteProviderError.authenticationRequired
        }
        let token = try await withCheckedThrowingContinuation { (continuation: TokenContinuation) in
            state.performAction { accessToken, _, error in
                if let accessToken {
                    continuation.resume(returning: accessToken)
                } else {
                    continuation.resume(
                        throwing: error ?? RemoteProviderError.authenticationRequired
                    )
                }
            }
        }
        try await persist(state)
        return token
    }

    func signOut() async throws {
        await authorizationFlow?.cancel()
        authorizationFlow = nil
        state = nil
        try await store.delete(key: key)
    }

    private func persist(
        _ state: OIDAuthState
    ) async throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: state,
            requiringSecureCoding: true
        )
        try await store.save(data, key: key)
    }
}
