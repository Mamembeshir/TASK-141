import XCTest
import CoreData
@testable import GreenGate

/// Low-stock detection and reservation math for InventoryService.
final class InventoryServiceTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var productService: ProductService!
    var inventoryService: InventoryService!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "store")
        container.loadPersistentStores { _, err in XCTAssertNil(err); exp.fulfill() }
        waitForExpectations(timeout: 5)
        context = container.viewContext
        productService = ProductService(context: context)
        inventoryService = InventoryService(context: context)
    }

    override func tearDownWithError() throws {
        productService = nil
        inventoryService = nil
        context = nil
        container = nil
    }

    private func makeContentManager() -> User {
        let u = User(context: context)
        u.id = UUID(); u.username = "cm-\(UUID().uuidString.prefix(5))"
        u.role = Role.contentManager.rawValue; u.status = UserStatus.active.rawValue
        u.version = 0; u.createdAt = Date()
        return u
    }

    private func seedSKU(barcode: String = "BC-\(UUID().uuidString.prefix(6))") throws -> ProductSKU {
        let actor = makeContentManager()
        let spu = try productService.createSPU(name: "Bouquet", description: nil,
                                               category: "Flowers", actor: actor)
        let sku = try productService.createSKU(
            spuID: spu.id, barcode: barcode, stemCount: 12, wrapType: nil,
            color: nil, priceCents: 2500, isTaxable: true, actor: actor
        )
        return sku
    }

    func test_adjustStock_positive_setsOnHand() throws {
        let sku = try seedSKU()
        let lot = try inventoryService.adjustStock(skuID: sku.id, quantity: 25,
                                                    reason: "receive", actorID: UUID())
        XCTAssertEqual(lot.onHand, 25)
    }

    func test_adjustStock_cannotGoNegative() throws {
        let sku = try seedSKU()
        _ = try inventoryService.adjustStock(skuID: sku.id, quantity: 3, reason: "receive", actorID: UUID())
        XCTAssertThrowsError(
            try inventoryService.adjustStock(skuID: sku.id, quantity: -10, reason: "shrink", actorID: UUID())
        )
    }

    func test_reserve_reducesAvailable() throws {
        let sku = try seedSKU()
        _ = try inventoryService.adjustStock(skuID: sku.id, quantity: 20, reason: "receive", actorID: UUID())
        try inventoryService.reserveStock(skuID: sku.id, quantity: 5)
        let avail = try inventoryService.getAvailable(skuID: sku.id)
        XCTAssertEqual(avail, 15)
    }

    func test_unreserve_restoresAvailable() throws {
        let sku = try seedSKU()
        _ = try inventoryService.adjustStock(skuID: sku.id, quantity: 20, reason: "receive", actorID: UUID())
        try inventoryService.reserveStock(skuID: sku.id, quantity: 5)
        try inventoryService.unreserveStock(skuID: sku.id, quantity: 5)
        XCTAssertEqual(try inventoryService.getAvailable(skuID: sku.id), 20)
    }

    func test_unreserve_belowZero_throws() throws {
        let sku = try seedSKU()
        _ = try inventoryService.adjustStock(skuID: sku.id, quantity: 5, reason: "receive", actorID: UUID())
        XCTAssertThrowsError(try inventoryService.unreserveStock(skuID: sku.id, quantity: 3))
    }

    // MARK: - Low stock (PROD-06, default 10)

    func test_checkLowStock_atOrBelowThreshold_included() throws {
        let low = try seedSKU(barcode: "LOW")
        _ = try inventoryService.adjustStock(skuID: low.id, quantity: 10, reason: "receive", actorID: UUID())

        let ok = try seedSKU(barcode: "OK")
        _ = try inventoryService.adjustStock(skuID: ok.id, quantity: 50, reason: "receive", actorID: UUID())

        let results = try inventoryService.checkLowStock()
        XCTAssertTrue(results.contains { $0.id == low.id })
        XCTAssertFalse(results.contains { $0.id == ok.id })
    }

    func test_checkLowStock_customThreshold() throws {
        let sku = try seedSKU()
        _ = try inventoryService.adjustStock(skuID: sku.id, quantity: 3, reason: "receive", actorID: UUID())
        XCTAssertTrue(try inventoryService.checkLowStock(threshold: 5).contains { $0.id == sku.id })
        XCTAssertFalse(try inventoryService.checkLowStock(threshold: 2).contains { $0.id == sku.id })
    }

    func test_checkLowStock_respectsReservations() throws {
        let sku = try seedSKU()
        _ = try inventoryService.adjustStock(skuID: sku.id, quantity: 12, reason: "receive", actorID: UUID())
        try inventoryService.reserveStock(skuID: sku.id, quantity: 5)
        // available = 7, threshold 10 → flagged.
        XCTAssertTrue(try inventoryService.checkLowStock().contains { $0.id == sku.id })
    }
}
