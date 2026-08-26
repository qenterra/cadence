import CryptoKit
import Foundation
import Security

protocol CadenceInstanceMessageAuthenticating: AnyObject {
    func signature(for paths: [String]) -> String
    func verifies(signature: String, paths: [String]) -> Bool
}

final class CadenceInstanceMessageAuthenticator: CadenceInstanceMessageAuthenticating {
    private static let service = "com.qenterra.cadence.instance-messaging"
    private static let account = "hmac-key-v1"

    private let key: SymmetricKey

    init() throws {
        key = try SymmetricKey(data: Self.loadOrCreateSecret())
    }

    init(secret: Data) {
        key = SymmetricKey(data: secret)
    }

    func signature(for paths: [String]) -> String {
        Data(
            HMAC<SHA256>.authenticationCode(
                for: payload(for: paths),
                using: key
            )
        ).base64EncodedString()
    }

    func verifies(signature: String, paths: [String]) -> Bool {
        guard let provided = Data(base64Encoded: signature) else {
            return false
        }
        let expected = Data(
            HMAC<SHA256>.authenticationCode(
                for: payload(for: paths),
                using: key
            )
        )
        guard provided.count == expected.count else {
            return false
        }
        return zip(provided, expected).reduce(UInt8(0)) { result, bytes in
            result | (bytes.0 ^ bytes.1)
        } == 0
    }
}

private extension CadenceInstanceMessageAuthenticator {
    func payload(for paths: [String]) -> Data {
        var payload = Data()
        for path in paths {
            let bytes = Data(path.utf8)
            var length = UInt32(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
            payload.append(bytes)
        }
        return payload
    }

    static func loadOrCreateSecret() throws -> Data {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let query = identity.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, latest in latest }
        var result: CFTypeRef?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &result)
        if readStatus == errSecSuccess,
           let secret = result as? Data,
           secret.count == 32 {
            return secret
        }
        guard readStatus == errSecItemNotFound else {
            throw RemoteProviderError.authenticationRequired
        }

        var secret = Data(repeating: 0, count: 32)
        let secretLength = secret.count
        let randomStatus = secret.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, secretLength, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw RemoteProviderError.authenticationRequired
        }
        var insertion = identity
        insertion[kSecValueData as String] = secret
        insertion[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let writeStatus = SecItemAdd(insertion as CFDictionary, nil)
        if writeStatus == errSecSuccess {
            return secret
        }
        guard writeStatus == errSecDuplicateItem else {
            throw RemoteProviderError.authenticationRequired
        }
        return try loadOrCreateSecret()
    }
}
