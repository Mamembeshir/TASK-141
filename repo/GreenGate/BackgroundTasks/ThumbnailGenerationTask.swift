import BackgroundTasks
import CoreData

final class ThumbnailGenerationTask {

    static let identifier = "com.greengate.thumbnailgeneration"

    static func scheduleIfNeeded() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
    }

    static func handle(task: BGProcessingTask) {
        scheduleIfNeeded()

        let context = CoreDataStack.shared.newBackgroundContext()

        task.expirationHandler = { task.setTaskCompleted(success: false) }

        context.perform {
            guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
                task.setTaskCompleted(success: true)
                return
            }

            let fetch = NSFetchRequest<Attachment>(entityName: "Attachment")
            fetch.predicate = NSPredicate(
                format: "thumbnailPath == nil AND (mimeType BEGINSWITH 'image/' OR mimeType BEGINSWITH 'video/')"
            )

            guard let attachments = try? context.fetch(fetch) else {
                task.setTaskCompleted(success: false)
                return
            }

            let base = AppConfiguration.applicationSupportDirectory

            for attachment in attachments {
                let fileURL = base.appendingPathComponent(attachment.filePath)
                let thumbnailURL = AppConfiguration.thumbnailsDirectory
                    .appendingPathComponent(attachment.id.uuidString + "_thumb.jpg")

                if let thumb = ThumbnailGenerator.generate(from: fileURL, outputURL: thumbnailURL) {
                    attachment.thumbnailPath = AppConfiguration.thumbnailsDirectory
                        .lastPathComponent + "/" + thumb.lastPathComponent
                }
            }

            try? context.save()
            task.setTaskCompleted(success: true)
        }
    }
}
