import BackgroundTasks
import CoreData

final class BulkImportTask {

    static let identifier = "com.greengate.bulkimport"

    private static let pendingImportURLKey   = "GreenGate.pendingImportURL"
    private static let pendingImportActorKey = "GreenGate.pendingImportActorID"
    private static let pendingImportExtKey   = "GreenGate.pendingImportExt"

    /// Persists `fileURL`, `actorID`, and the file extension so the background
    /// handler can branch between CSV and XLSX parsing.
    static func schedulePendingImport(fileURL: URL, actorID: UUID) {
        UserDefaults.standard.set(fileURL.path,                          forKey: pendingImportURLKey)
        UserDefaults.standard.set(actorID.uuidString,                    forKey: pendingImportActorKey)
        UserDefaults.standard.set(fileURL.pathExtension.lowercased(),    forKey: pendingImportExtKey)
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func handle(task: BGProcessingTask) {
        guard
            let path    = UserDefaults.standard.string(forKey: pendingImportURLKey),
            let actorStr = UserDefaults.standard.string(forKey: pendingImportActorKey),
            let actorID = UUID(uuidString: actorStr)
        else {
            task.setTaskCompleted(success: true)
            return
        }

        let fileURL = URL(fileURLWithPath: path)

        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            // Re-schedule; checkpoint (file path + actor) is already persisted.
            let request = BGProcessingTaskRequest(identifier: identifier)
            request.requiresNetworkConnectivity = false
            try? BGTaskScheduler.shared.submit(request)
            task.setTaskCompleted(success: true)
            return
        }

        // Set the expiration handler BEFORE starting work so the system can
        // interrupt cleanly. The persisted URL+actorID act as the checkpoint —
        // the next launch of this task will resume from the same file.
        task.expirationHandler = {
            // Work is checkpointed via UserDefaults; just signal incomplete.
            task.setTaskCompleted(success: false)
        }

        let context = CoreDataStack.shared.newBackgroundContext()
        let service = ImportExportService(context: context)

        let ext = UserDefaults.standard.string(forKey: pendingImportExtKey) ?? ""

        context.perform {
            do {
                // Fetch the actor User from Core Data so role enforcement applies.
                let request = NSFetchRequest<User>(entityName: "User")
                request.predicate = NSPredicate(format: "id == %@", actorID as CVarArg)
                guard let actor = try context.fetch(request).first else {
                    task.setTaskCompleted(success: false)
                    return
                }
                if ext == "xlsx" {
                    _ = try service.importProductsXLSX(at: fileURL, actor: actor)
                } else {
                    _ = try service.importProductsCSV(at: fileURL, actor: actor)
                }
                // Import succeeded — clear the checkpoint so it is not retried.
                UserDefaults.standard.removeObject(forKey: pendingImportURLKey)
                UserDefaults.standard.removeObject(forKey: pendingImportActorKey)
                UserDefaults.standard.removeObject(forKey: pendingImportExtKey)
                task.setTaskCompleted(success: true)
            } catch {
                // Leave the checkpoint in place so a future task run can retry.
                task.setTaskCompleted(success: false)
            }
        }
    }
}
