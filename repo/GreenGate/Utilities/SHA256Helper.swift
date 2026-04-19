import Foundation
import CryptoKit

enum SHA256Helper {

    /// Returns the lowercase hex SHA-256 hash of the given string.
    static func hash(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the lowercase hex SHA-256 hash of the given data.
    static func hash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the SHA-256 hash of a file at the given URL.
    /// Returns nil if the file cannot be read.
    static func hashFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return hash(data)
    }
}
