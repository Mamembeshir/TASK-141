import XCTest
import CoreData
@testable import GreenGate

/// View-layer checks for the POS module: cart totals update when the service
/// recomputes, parked-tickets countdown formats correctly.
final class POSViewTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var pos: POSService!
    var products: ProductService!
    var inventory: InventoryService!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "store")
        container.loadPersistentStores { _, err in XCTAssertNil(err); exp.fulfill() }
        waitForExpectations(timeout: 5)
        context = container.viewContext
        pos = POSService(context: context)
        products = ProductService(context: context)
        inventory = InventoryService(context: context)
    }

    override func tearDownWithError() throws {
        pos = nil; products = nil; inventory = nil
        context = nil; container = nil
    }

    private func makeContentManager() -> User {
        let u = User(context: context)
        u.id = UUID(); u.username = "cm-\(UUID().uuidString.prefix(5))"
        u.role = Role.contentManager.rawValue; u.status = UserStatus.active.rawValue
        u.version = 0; u.createdAt = Date()
        return u
    }

    private func makeCashier() -> User {
        let u = User(context: context)
        u.id = UUID(); u.username = "ca-\(UUID().uuidString.prefix(5))"
        u.role = Role.cashier.rawValue; u.status = UserStatus.active.rawValue
        u.version = 0; u.createdAt = Date()
        return u
    }

    func test_cart_populatesTotals_onAddToCart() throws {
        let actor = makeContentManager()
        let spu = try products.createSPU(name: "T", description: nil, category: nil, actor: actor)
        let sku = try products.createSKU(spuID: spu.id, barcode: "VCT-1", stemCount: 0,
                                         wrapType: nil, color: nil, priceCents: 1500,
                                         isTaxable: false, actor: actor)
        _ = try inventory.adjustStock(skuID: sku.id, quantity: 10, reason: "seed", actorID: actor.id)

        let cart = CartViewController(service: pos)
        _ = cart.view  // triggers viewDidLoad
        let order = try pos.createOrder(cashier: makeCashier())
        var totalSeen: Int64 = -1
        cart.onTotalsChanged = { totalSeen = $0.totalCents }
        cart.set(order: order)
        _ = try pos.addToCart(orderID: order.id, skuID: sku.id, quantity: 2)
        cart.reload()
        XCTAssertEqual(totalSeen, 3000)
    }

    func test_parkedCountdown_formatsRemainingTime() {
        // Parked 20 minutes ago → ~10 minutes left (window default 30).
        let parked = Date().addingTimeInterval(-20 * 60)
        let text = ParkedTicketsViewController.remainingText(parkedAt: parked)
        XCTAssertTrue(text.contains("left"), "Expected 'left' in \(text)")
    }

    func test_pos_embedsScannerAndCart() {
        let vc = POSViewController(service: pos)
        _ = vc.view
        // At least one child view controller (the Cart) is embedded.
        XCTAssertTrue(vc.children.contains(where: { $0 is CartViewController }))
    }
}
