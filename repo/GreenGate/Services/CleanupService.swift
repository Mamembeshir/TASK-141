import CoreData
import Foundation

/// Orphan-file cleanup (ATT-06): files in Application Support/Attachments with
/// no Core Data `Attachment` reference, older than `orphanCleanupDays` (default
/// 7), are deleted. Called from `OrphanCleanupTask` on a BGProcessingTask.
final class CleanupService {

    static let shared = CleanupService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    struct CleanupReport: Equatable {
        let scanned: Int
        let removed: Int
    }

    /// Enumerates all files under Attachments/ and removes any whose path does
    /// not correspond to a known attachment and whose modified time is older
    /// than the configured cutoff.
    @discardableResult
    func cleanOrphans(now: Date = Date()) throws -> CleanupReport {
        let base = AppConfiguration.applicationSupportDirectory
            .appendingPathComponent("Attachments", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else {
            return CleanupReport(scanned: 0, removed: 0)
        }

        let cutoff = Calendar.current.date(
            byAdding: .day, value: -AppConfiguration.orphanCleanupDays, to: now
        ) ?? now

        // Known attachment paths (relative to Application Support).
        let req = NSFetchRequest<Attachment>(entityName: "Attachment")
        let known = Set((try context.fetch(req)).map { $0.filePath })

        var scanned = 0
        var removed = 0

        let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey,
                                                          .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            scanned += 1
            let modified = values.contentModificationDate ?? Date()
            let relative = url.path.replacingOccurrences(
                of: AppConfiguration.applicationSupportDirectory.path + "/", with: ""
            )
            if known.contains(relative) { continue }
            if modified > cutoff { continue }
            try? fm.removeItem(at: url)
            removed += 1
        }
        return CleanupReport(scanned: scanned, removed: removed)
    }
}
