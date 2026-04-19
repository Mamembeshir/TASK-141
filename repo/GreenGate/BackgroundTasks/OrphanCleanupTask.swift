import BackgroundTasks
import CoreData

final class OrphanCleanupTask {

    static let identifier = "com.greengate.orphancleanup"

    static func scheduleIfNeeded() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 24, to: Date())
        try? BGTaskScheduler.shared.submit(request)
    }

    static func handle(task: BGProcessingTask) {
        // Re-schedule the next daily run before doing any work.
        scheduleIfNeeded()

        task.expirationHandler = { task.setTaskCompleted(success: false) }

        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            task.setTaskCompleted(success: true)
            return
        }

        // Delegate entirely to CleanupService, which correctly identifies
        // orphans by checking whether a file has a matching Attachment row —
        // NOT by deleting every Attachment older than a threshold (ATT-06).
        let context = CoreDataStack.shared.newBackgroundContext()
        let service = CleanupService(context: context)
        context.perform {
            _ = try? service.cleanOrphans()
            task.setTaskCompleted(success: true)
        }
    }
}
