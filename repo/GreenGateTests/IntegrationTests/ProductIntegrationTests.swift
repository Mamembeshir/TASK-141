import XCTest
import CoreData
@testable import GreenGate

/// End-to-end product lifecycle against an in-memory Core Data store.
/// Covers: draft → pending → listed, reject → draft, delist flow,
/// stock adjustment, reservation, low-stock alert at ≤ 10.
final class ProductIntegrationTests: XCTestCase {

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

    private func reviewer() -> User {
        let u = User(context: context)
        u.id = UUID(); u.username = "rv-\(UUID().uuidString.prefix(5))"
        u.role = Role.reviewer.rawValue; u.status = UserStatus.active.rawValue
        u.version = 0; u.createdAt = Date()
        return u
    }

    private func contentManager() -> User {
        let u = User(context: context)
        u.id = UUID(); u.username = "cm-\(UUID().uuidString.prefix(5))"
        u.role = Role.contentManager.rawValue; u.status = UserStatus.active.rawValue
        u.version = 0; u.createdAt = Date()
        return u
    }

    // MARK: - Approve flow

    func test_create_submit_approve_transitionsToListed() throws {
        let cm = contentManager()
        let rv = reviewer()

        let spu = try productService.createSPU(name: "Spring Bouquet", description: nil,
                                               category: "Flowers", actor: cm)
        try productService.createSKU(
            spuID: spu.id, barcode: "SB-12-P", stemCount: 12, wrapType: "paper",
            color: "pink", priceCents: 2500, isTaxable: true, actor: cm
        )
        try productService.submitForApproval(spuID: spu.id, actor: cm)
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.pendingApproval.rawValue)

        try productService.approve(spuID: spu.id, reviewerID: rv.id, reviewer: rv)
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.listed.rawValue)
        XCTAssertTrue(spu.isListed)

        // Audit contains APPROVE for this SPU.
        let fetch = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        fetch.predicate = NSPredicate(format: "entityID == %@ AND action == %@",
                                      spu.id as CVarArg, AuditAction.approve)
        XCTAssertGreaterThanOrEqual(try context.fetch(fetch).count, 1)
    }

    func test_reject_returnsToDraftWithNotes() throws {
        let cm = contentManager()
        let rv = reviewer()
        let spu = try productService.createSPU(name: "Rose", description: nil,
                                               category: "Flowers", actor: cm)
        try productService.createSKU(spuID: spu.id, barcode: "RX-1", stemCount: 6,
                                     wrapType: nil, color: "red", priceCents: 1500,
                                     isTaxable: true, actor: cm)
        try productService.submitForApproval(spuID: spu.id, actor: cm)
        try productService.reject(spuID: spu.id, reviewerID: rv.id,
                                  reviewer: rv, notes: "Missing description")
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.draft.rawValue)
        XCTAssertEqual(spu.rejectionNotes, "Missing description")
    }

    // MARK: - Delist flow

    func test_delistFlow_transitionsListedToDelisted() throws {
        let cm = contentManager()
        let rv = reviewer()
        let spu = try productService.createSPU(name: "Lily", description: nil,
                                               category: "Flowers", actor: cm)
        try productService.createSKU(spuID: spu.id, barcode: "LY-1", stemCount: 3,
                                     wrapType: nil, color: "white", priceCents: 1200,
                                     isTaxable: true, actor: cm)
        try productService.submitForApproval(spuID: spu.id, actor: cm)
        try productService.approve(spuID: spu.id, reviewerID: rv.id, reviewer: rv)

        try productService.requestDelist(spuID: spu.id, actor: cm)
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.pendingApproval.rawValue)
        XCTAssertTrue(spu.pendingDelist)

        try productService.approveDelist(spuID: spu.id, reviewerID: rv.id, reviewer: rv)
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.delisted.rawValue)
    }

    // MARK: - Inventory

    func test_adjustStock_updatesOnHand() throws {
        let cm = contentManager()
        let spu = try productService.createSPU(name: "X", description: nil,
                                               category: nil, actor: cm)
        let sku = try productService.createSKU(spuID: spu.id, barcode: "X-1",
                                               stemCount: 0, wrapType: nil,
                                               color: nil, priceCents: 100,
                                               isTaxable: false, actor: cm)
        let lot = try inventoryService.adjustStock(skuID: sku.id, quantity: 50,
                                                    reason: "receive", actorID: cm.id)
        XCTAssertEqual(lot.onHand, 50)
        XCTAssertEqual(try inventoryService.getAvailable(skuID: sku.id), 50)
    }

    func test_reserve_reducesAvailable() throws {
        let cm = contentManager()
        let spu = try productService.createSPU(name: "Y", description: nil,
                                               category: nil, actor: cm)
        let sku = try productService.createSKU(spuID: spu.id, barcode: "Y-1",
                                               stemCount: 0, wrapType: nil,
                                               color: nil, priceCents: 100,
                                               isTaxable: false, actor: cm)
        _ = try inventoryService.adjustStock(skuID: sku.id, quantity: 30, reason: "receive", actorID: cm.id)
        try inventoryService.reserveStock(skuID: sku.id, quantity: 8)
        XCTAssertEqual(try inventoryService.getAvailable(skuID: sku.id), 22)
    }

    func test_lowStockAlert_firesAtThreshold() throws {
        let cm = contentManager()
        let spu = try productService.createSPU(name: "Z", description: nil,
                                               category: nil, actor: cm)
        let sku = try productService.createSKU(spuID: spu.id, barcode: "Z-1",
                                               stemCount: 0, wrapType: nil,
                                               color: nil, priceCents: 100,
                                               isTaxable: false, actor: cm)
        _ = try inventoryService.adjustStock(skuID: sku.id, quantity: 10, reason: "receive", actorID: cm.id)
        let lows = try inventoryService.checkLowStock()  // threshold 10
        XCTAssertTrue(lows.contains { $0.id == sku.id })
    }

    func test_lowStockAlert_doesNotFireAboveThreshold() throws {
        let cm = contentManager()
        let spu = try productService.createSPU(name: "W", description: nil,
                                               category: nil, actor: cm)
        let sku = try productService.createSKU(spuID: spu.id, barcode: "W-1",
                                               stemCount: 0, wrapType: nil,
                                               color: nil, priceCents: 100,
                                               isTaxable: false, actor: cm)
        _ = try inventoryService.adjustStock(skuID: sku.id, quantity: 25, reason: "receive", actorID: cm.id)
        let lows = try inventoryService.checkLowStock()
        XCTAssertFalse(lows.contains { $0.id == sku.id })
    }

    // MARK: - Authorization negative tests (Finding 1 & 4)

    func test_createSPU_byReviewer_throwsInsufficientPermissions() throws {
        let rv = reviewer()
        XCTAssertThrowsError(
            try productService.createSPU(name: "Flower", description: nil,
                                         category: nil, actor: rv)
        ) { err in
            if case ProductError.insufficientPermissions = err { } else {
                XCTFail("expected insufficientPermissions, got \(err)")
            }
        }
    }

    func test_submitForApproval_byReviewer_throwsInsufficientPermissions() throws {
        let cm = contentManager()
        let rv = reviewer()
        let spu = try productService.createSPU(name: "Rose", description: nil,
                                               category: nil, actor: cm)
        try productService.createSKU(spuID: spu.id, barcode: "NEG-IT-1", stemCount: 1,
                                     wrapType: nil, color: nil, priceCents: 100,
                                     isTaxable: false, actor: cm)
        XCTAssertThrowsError(
            try productService.submitForApproval(spuID: spu.id, actor: rv)
        ) { err in
            if case ProductError.insufficientPermissions = err { } else {
                XCTFail("expected insufficientPermissions, got \(err)")
            }
        }
    }
}
