import Foundation

/// Monitors and enforces attachment storage quota.
enum FileQuotaManager {

    /// Total attachment quota: 2 GB.
    static let quotaBytes: Int64 = 2 * 1024 * 1024 * 1024

    /// Returns the total bytes used in the attachments directory.
    static var usedBytes: Int64 {
        let fm = FileManager.default
        let base = AppConfiguration.attachmentsDirectory

        guard let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    /// Returns true if adding `bytes` would stay within quota.
    static func hasCapacity(for bytes: Int64) -> Bool {
        usedBytes + bytes <= quotaBytes
    }

    /// Formatted string of used / total capacity.
    static var usageSummary: String {
        let used  = Double(usedBytes) / (1024 * 1024 * 1024)
        let total = Double(quotaBytes) / (1024 * 1024 * 1024)
        return String(format: "%.2f GB / %.1f GB used", used, total)
    }
}
