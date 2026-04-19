import Foundation
import Security
import CryptoKit

final class KeychainHelper {

    static let shared = KeychainHelper()
    private init() {}

    private let service = "com.greengate.app"

    // MARK: - Password Hashing & Storage

    /// Hashes password with SHA-256 + user ID salt and stores in Keychain.
    func storePasswordHash(for userID: String, password: String) {
        let hash = SHA256Helper.hash("\(userID):\(password)")
        store(value: hash, account: passwordAccount(userID: userID))
    }

    /// Returns true if the provided password matches the stored hash for this userID.
    func verifyPassword(for userID: String, password: String) -> Bool {
        guard let stored = retrieve(account: passwordAccount(userID: userID)) else { return false }
        let hash = SHA256Helper.hash("\(userID):\(password)")
        return stored == hash
    }

    func deletePasswordHash(for userID: String) {
        delete(account: passwordAccount(userID: userID))
    }

    // MARK: - HMAC Secret Key

    /// Returns the HMAC-SHA256 signing key, generating and storing it on first call.
    var ticketSigningKey: Data {
        if let stored = retrieveData(account: "ticketSigningKey") {
            return stored
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        storeData(data, account: "ticketSigningKey")
        return data
    }

    // MARK: - Generic Store / Retrieve / Delete

    func store(value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        storeData(data, account: account)
    }

    func retrieve(account: String) -> String? {
        guard let data = retrieveData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Private Data Helpers

    private func storeData(_ data: Data, account: String) {
        delete(account: account)
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     account,
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func retrieveData(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    // MARK: - Helpers

    private func passwordAccount(userID: String) -> String { "password.\(userID)" }
}
