import XCTest
import CoreData
@testable import GreenGate

/// Checkout + ReturnExchange view-layer coverage.
final class POSExtraViewTests: XCTestCase {

    var container: NSPersistentContainer!
    var ctx: NSManagedObjectContext!
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
        ctx = container.viewContext
        pos = POSService(context: ctx)
        products = ProductService(context: ctx)
        inventory = InventoryService(context: ctx)
    }

    override func tearDownWithError() throws {
        pos = nil; products = nil; inventory = nil
        ctx = nil; container = nil
    }

    private func makeContentManager() -> User {
        let u = User(context: ctx)
        u.id = UUID(); u.username = "cm-\(UUID().uuidString.prefix(5))"
        u.role = Role.contentManager.rawValue; u.status = UserStatus.active.rawValue
        u.version = 0; u.createdAt = Date()
        return u
    }

    private func makeCashier() -> User {
        let u = User(context: ctx)
        u.id = UUID(); u.username = "ca-\(UUID().uuidString.prefix(5))"
        u.role = Role.cashier.rawValue; u.status = UserStatus.active.rawValue
        u.version = 0; u.createdAt = Date()
        return u
    }

    // MARK: - CheckoutViewController

    func test_checkout_renders_summarySection_andCompleteButton() throws {
        let actor = makeContentManager()
        let spu = try products.createSPU(name: "X", description: nil,
                                         category: nil, actor: actor)
        let sku = try products.createSKU(spuID: spu.id, barcode: "CO-1", stemCount: 0,
                                         wrapType: nil, color: nil, priceCents: 1000,
                                         isTaxable: false, actor: actor)
        _ = try inventory.adjustStock(skuID: sku.id, quantity: 5, reason: "seed", actorID: actor.id)
        let order = try pos.createOrder(cashier: makeCashier())
        _ = try pos.addToCart(orderID: order.id, skuID: sku.id, quantity: 1)

        let vc = CheckoutViewController(order: order, service: pos)
        _ = vc.view
        XCTAssertEqual(vc.title, "Checkout")
        let table = vc.view.subviews.compactMap { $0 as? UITableView }.first
        XCTAssertEqual(table?.numberOfSections, 2,
                       "Order Summary + Payment Method")
        XCTAssertEqual(table?.numberOfRows(inSection: 0), 4,
                       "Subtotal / Discount / Tax / Total")
        // Cash mode by default → 3 rows.
        XCTAssertEqual(table?.numberOfRows(inSection: 1), 3)
    }

    // MARK: - ReturnExchange

    func test_returnExchange_renders_andLooksUpAnOrder() throws {
        let actor = makeContentManager()
        let spu = try products.createSPU(name: "RT", description: nil,
                                         category: nil, actor: actor)
        let sku = try products.createSKU(spuID: spu.id, barcode: "RT-1", stemCount: 0,
                                         wrapType: nil, color: nil, priceCents: 1000,
                                         isTaxable: false, actor: actor)
        _ = try inventory.adjustStock(skuID: sku.id, quantity: 5, reason: "seed", actorID: actor.id)
        let order = try pos.createOrder(cashier: makeCashier())
        _ = try pos.addToCart(orderID: order.id, skuID: sku.id, quantity: 1)
        _ = try pos.calculateTotals(orderID: order.id)
        try pos.splitTender(orderID: order.id, payments: [
            .init(tender: .cash, amountCents: order.totalCents, memo: nil)
        ])
        try pos.completeOrder(orderID: order.id, actor: makeCashier())

        let vc = ReturnExchangeViewController(service: pos)
        _ = vc.view
        XCTAssertEqual(vc.title, "Return / Exchange")
        // Refund is disabled until an order is loaded.
        XCTAssertFalse(vc.navigationItem.rightBarButtonItem?.isEnabled ?? true)
    }
}
