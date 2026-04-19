import XCTest
import CoreData
@testable import GreenGate

/// Tests Core Data setup using an in-memory store.
final class CoreDataStackIntegrationTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        let expectation = self.expectation(description: "Store loaded")
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)
        context = container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func test_createUser_succeeds() throws {
        let user = User(context: context)
        user.id       = UUID()
        user.username = "testuser"
        user.role     = Role.cashier.rawValue
        user.status   = UserStatus.active.rawValue
        user.failedLoginCount = 0
        user.biometricEnabled = false
        user.version  = 0
        user.createdAt = Date()

        XCTAssertNoThrow(try context.save())

        let fetch = NSFetchRequest<User>(entityName: "User")
        fetch.predicate = NSPredicate(format: "username == %@", "testuser")
        let results = try context.fetch(fetch)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.username, "testuser")
    }

    func test_auditLog_appendsCorrectly() throws {
        let log = AuditLog(context: context)
        log.id = UUID()
        log.actorID = UUID()
        log.action = AuditAction.create
        log.entityType = "User"
        log.entityID = UUID()
        log.timestamp = Date()

        XCTAssertNoThrow(try context.save())

        let fetch = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        XCTAssertEqual(try context.count(for: fetch), 1)
    }

    func test_inventoryLot_availableComputed() throws {
        let spu = ProductSPU(context: context)
        spu.id = UUID()
        spu.name = "Test SPU"
        spu.isListed = true
        spu.listingStatus = ProductListingStatus.listed.rawValue
        spu.version = 0
        spu.createdAt = Date()

        let sku = ProductSKU(context: context)
        sku.id = UUID()
        sku.barcode = "TEST-001"
        sku.priceCents = 1000
        sku.isTaxable = true
        sku.isActive = true
        sku.version = 0
        sku.spu = spu

        let lot = InventoryLot(context: context)
        lot.id = UUID()
        lot.onHand = 20
        lot.reservedCount = 5
        lot.lotDate = Date()
        lot.version = 0
        lot.sku = sku

        try context.save()

        XCTAssertEqual(lot.available, 15)
    }
}
