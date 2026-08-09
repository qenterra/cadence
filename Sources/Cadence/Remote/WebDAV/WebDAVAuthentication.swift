import Foundation
import Security

struct WebDAVCredentials: Codable, Equatable, Sendable {
    let username: String
    let password: String
}

protocol WebDAVCredentialStoring: Sendable {
    func load(key: String) async throws -> WebDAVCredentials?
    func save(
        _ credentials: WebDAVCredentials,
        key: String
    ) async throws
    func delete(key: String) async throws
}

actor KeychainWebDAVCredentialStore: WebDAVCredentialStoring {
    private let service: String

    init(service: String = "com.qenterra.cadence.webdav") {
        self.service = service
    }

    func load(
        key: String
    ) async throws -> WebDAVCredentials? {
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
        return try JSONDecoder().decode(WebDAVCredentials.self, from: data)
    }

    func save(
        _ credentials: WebDAVCredentials,
        key: String
    ) async throws {
        let data = try JSONEncoder().encode(credentials)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insertion = identity
            attributes.forEach { insertion[$0.key] = $0.value }
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
                throw RemoteProviderError.authenticationRequired
            }
        } else if updateStatus != errSecSuccess {
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

actor WebDAVAuthentication {
    private let key: String
    private let store: any WebDAVCredentialStoring
    private var credentials: WebDAVCredentials?

    init(
        key: String,
        store: any WebDAVCredentialStoring = KeychainWebDAVCredentialStore()
    ) {
        self.key = key
        self.store = store
    }

    func restore() async throws {
        guard let restored = try await store.load(key: key) else {
            throw RemoteProviderError.authenticationRequired
        }
        credentials = restored
    }

    func signIn(
        _ credentials: WebDAVCredentials
    ) async throws {
        guard !credentials.username.isEmpty,
              !credentials.password.isEmpty
        else {
            throw RemoteProviderError.authenticationRequired
        }
        try await store.save(credentials, key: key)
        self.credentials = credentials
    }

    func signOut() async throws {
        credentials = nil
        try await store.delete(key: key)
    }

    func authorizationHeader() -> String? {
        guard let credentials else {
            return nil
        }
        let token = Data(
            "\(credentials.username):\(credentials.password)".utf8
        ).base64EncodedString()
        return "Basic \(token)"
    }
}
