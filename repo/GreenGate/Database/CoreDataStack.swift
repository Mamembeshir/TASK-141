import CoreData

final class CoreDataStack {

    static let shared = CoreDataStack()

    private init() {}

    // MARK: - Persistent Container

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "GreenGate")

        // SQLite store in Application Support
        let storeURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("GreenGate.sqlite")

        let storeDescription = NSPersistentStoreDescription(url: storeURL)
        storeDescription.type = NSSQLiteStoreType
        storeDescription.shouldMigrateStoreAutomatically = true
        storeDescription.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [storeDescription]

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved Core Data error: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return container
    }()

    // MARK: - Contexts

    /// Main queue context — use for reads and UI binding.
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    /// Creates a new private-queue background context for writes.
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    // MARK: - Save Helpers

    /// Saves the view context if it has changes.
    func saveViewContext() throws {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw CoreDataError.saveFailed(underlying: error)
        }
    }

    /// Saves the given background context if it has changes.
    /// Must be called from within `context.perform` / `context.performAndWait`.
    func save(context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw CoreDataError.saveFailed(underlying: error)
        }
    }

    // MARK: - Optimistic Locking

    /// Verifies that the version of a managed object matches the expected version,
    /// then increments it before saving. Throws `CoreDataError.staleRecord` on mismatch.
    func checkAndIncrementVersion<T: NSManagedObject>(
        object: T,
        expectedVersion: Int64,
        versionKeyPath: WritableKeyPath<T, Int64>
    ) throws {
        var mutable = object
        let current = mutable[keyPath: versionKeyPath]
        guard current == expectedVersion else {
            throw CoreDataError.staleRecord(entityType: String(describing: T.self))
        }
        mutable[keyPath: versionKeyPath] = current + 1
    }
}
