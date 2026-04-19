import Foundation

/// App-wide feature flags and configurable thresholds.
/// Admin-configurable values are stored in UserDefaults under the keys defined here.
enum AppConfiguration {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lowStockThreshold    = "GreenGate.lowStockThreshold"
        static let taxRateBasisPoints   = "GreenGate.taxRateBasisPoints"   // rate × 10000
        static let parkedOrderExpiryMin = "GreenGate.parkedOrderExpiryMin"
        static let returnWindowDays     = "GreenGate.returnWindowDays"
        static let discountCapPercent   = "GreenGate.discountCapPercent"
        static let importQualityMin     = "GreenGate.importQualityMin"
        static let orphanCleanupDays    = "GreenGate.orphanCleanupDays"
    }

    // MARK: - Defaults

    /// Low-stock alert threshold (units). Default: 10.
    static var lowStockThreshold: Int32 {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.lowStockThreshold)
            return v == 0 ? 10 : Int32(v)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: Keys.lowStockThreshold) }
    }

    /// Tax rate stored as basis points (rate × 10000). Default: 88750 = 8.875%.
    static var taxRateBasisPoints: Int32 {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.taxRateBasisPoints)
            return v == 0 ? 88750 : Int32(v)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: Keys.taxRateBasisPoints) }
    }

    /// Tax rate as a Double for calculation. e.g. 0.08875.
    static var taxRate: Double {
        Double(taxRateBasisPoints) / 1_000_000.0
    }

    /// Minutes before a parked order auto-expires. Default: 30.
    static var parkedOrderExpiryMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.parkedOrderExpiryMin)
            return v == 0 ? 30 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.parkedOrderExpiryMin) }
    }

    /// Days within which returns are allowed. Default: 30.
    static var returnWindowDays: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.returnWindowDays)
            return v == 0 ? 30 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.returnWindowDays) }
    }

    /// Maximum per-item or order-level discount percent. Default: 30.
    static var discountCapPercent: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.discountCapPercent)
            return v == 0 ? 30 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.discountCapPercent) }
    }

    /// Minimum quality score for CSV import rows. Default: 70.
    static var importQualityMinScore: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.importQualityMin)
            return v == 0 ? 70 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.importQualityMin) }
    }

    /// Days before orphan files are deleted. Default: 7.
    static var orphanCleanupDays: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.orphanCleanupDays)
            return v == 0 ? 7 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.orphanCleanupDays) }
    }

    // MARK: - System Actor

    /// Fixed sentinel actor ID used when no authenticated user is present —
    /// e.g. background tasks, automated sweepers, system-initiated writes.
    /// Never corresponds to a real User record.
    static let systemActorID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    // MARK: - App Sandbox Directories

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static var attachmentsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Attachments", isDirectory: true)
    }

    static var thumbnailsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    static var exportsDirectory: URL {
        documentsDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    /// Staging area for import files that will be processed by a background task.
    /// Files here persist across app launches so `BulkImportTask` can pick them up.
    static var importStagingDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("ImportStaging", isDirectory: true)
    }

    /// Files larger than this threshold are handed off to the background task rather
    /// than processed synchronously on the main thread.
    static let backgroundImportThresholdBytes: Int = 512 * 1024   // 512 KB

    static func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        [attachmentsDirectory, thumbnailsDirectory, exportsDirectory, importStagingDirectory].forEach { url in
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }
}
