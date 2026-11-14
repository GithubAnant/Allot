import CommonCrypto
import Foundation
import LocalAuthentication
import Security

/// Cursor's versioned safeStorage format; credentials never leave memory or their original store.
enum CursorCredentials {
    static func token(database: String, allowInteraction: Bool = false) async throws -> String {
        let data = try await Command.run("/usr/bin/sqlite3", ["-readonly", database, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"])
        let stored = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stored.isEmpty else { throw UsageFailure(L.text("Sign in to Cursor first.")) }
        let prefix = "cursor-safe-storage:v1:"
        if !stored.hasPrefix(prefix) {
            guard stored.split(separator: ".").count == 3 else { throw UsageFailure(L.text("Sign in to Cursor first.")) }
            return stored
        }
        guard let encrypted = Data(base64Encoded: String(stored.dropFirst(prefix.count))) else { throw UsageFailure("Cursor credential encoding is unsupported.") }
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Cursor Safe Storage", kSecAttrAccount as String: "Cursor Key", kSecReturnData as String: true]
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let password = result as? Data else {
            throw UsageFailure("Open Accounts and choose Sign in for Cursor to allow Keychain access.")
        }
        return try decrypt(encrypted, password: password)
    }
    static func decrypt(_ encrypted: Data, password: Data) throws -> String {
        guard encrypted.starts(with: Data("v10".utf8)), encrypted.count > 3, (encrypted.count - 3) % kCCBlockSizeAES128 == 0 else { throw UsageFailure("Cursor credential encryption is unsupported.") }
        let salt = Data("saltysalt".utf8), iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var key = Data(count: kCCKeySizeAES128)
        let status = key.withUnsafeMutableBytes { output in
            password.withUnsafeBytes { password in
                salt.withUnsafeBytes { salt in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.baseAddress?.assumingMemoryBound(to: Int8.self), password.count, salt.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, output.baseAddress?.assumingMemoryBound(to: UInt8.self), output.count)
                }
            }
        }
        guard status == kCCSuccess else { throw UsageFailure("Cursor credential decryption failed.") }
        let ciphertext = Data(encrypted.dropFirst(3))
        var plain = Data(count: ciphertext.count + kCCBlockSizeAES128), written = 0
        let capacity = plain.count
        let decrypted = plain.withUnsafeMutableBytes { output in
            key.withUnsafeBytes { key in
                iv.withUnsafeBytes { iv in
                    ciphertext.withUnsafeBytes { input in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), key.baseAddress, key.count, iv.baseAddress, input.baseAddress, input.count, output.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard decrypted == kCCSuccess, let token = String(data: plain.prefix(written), encoding: .utf8), token.split(separator: ".").count == 3 else { throw UsageFailure("Cursor credential decryption failed.") }
        return token
    }
}
