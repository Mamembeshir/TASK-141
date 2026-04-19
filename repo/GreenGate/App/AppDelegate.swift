import UIKit
import BackgroundTasks

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        NSSetUncaughtExceptionHandler { exception in
            #if DEBUG
            // Verbose logging in debug builds: safe for development, never ships.
            NSLog("💥 UNCAUGHT EXCEPTION: %@ — %@\nUserInfo: %@\nStack:\n%@",
                  exception.name.rawValue,
                  exception.reason ?? "(no reason)",
                  String(describing: exception.userInfo ?? [:]),
                  exception.callStackSymbols.joined(separator: "\n"))
            #else
            // Release: log only the exception name — no userInfo or stack symbols
            // that could expose sensitive runtime values.
            NSLog("UNCAUGHT EXCEPTION: %@", exception.name.rawValue)
            #endif
        }
        AppConfiguration.createDirectoriesIfNeeded()
        registerBackgroundTasks()
        OrphanCleanupTask.scheduleIfNeeded()
        EndOfDaySummaryTask.scheduleIfNeeded()
        ThumbnailGenerationTask.scheduleIfNeeded()
        seedDataIfNeeded()
        return true
    }

    // MARK: - UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {}

    // MARK: - Memory Warning

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        NotificationCenter.default.post(name: .didReceiveMemoryWarning, object: nil)
    }

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: OrphanCleanupTask.identifier,
            using: nil
        ) { task in
            OrphanCleanupTask.handle(task: task as! BGProcessingTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: EndOfDaySummaryTask.identifier,
            using: nil
        ) { task in
            EndOfDaySummaryTask.handle(task: task as! BGProcessingTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: ThumbnailGenerationTask.identifier,
            using: nil
        ) { task in
            ThumbnailGenerationTask.handle(task: task as! BGProcessingTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BulkImportTask.identifier,
            using: nil
        ) { task in
            BulkImportTask.handle(task: task as! BGProcessingTask)
        }
    }

    // MARK: - Seeding

    private func seedDataIfNeeded() {
        let context = CoreDataStack.shared.newBackgroundContext()
        Seeder.seedIfNeeded(context: context)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didReceiveMemoryWarning = Notification.Name("GreenGate.didReceiveMemoryWarning")
    static let inventoryDidChange      = Notification.Name("GreenGate.inventoryDidChange")
    static let orderStatusDidChange    = Notification.Name("GreenGate.orderStatusDidChange")
    static let ticketStatusDidChange   = Notification.Name("GreenGate.ticketStatusDidChange")
    static let propertyStatusDidChange = Notification.Name("GreenGate.propertyStatusDidChange")
    static let authStateDidChange      = Notification.Name("GreenGate.authStateDidChange")
}
