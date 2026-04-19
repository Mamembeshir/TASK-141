import XCTest
import CoreData
@testable import GreenGate

/// End-to-end POS flows: scan → cart → discount → coupon → split tender →
/// complete; park → expire → void; return within window; return past window.
final class POSIntegrationTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var pos: POSService!
    var products: ProductService!
    var inventory: InventoryService!
    var parkedSweeper: ParkedTicketService!

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
        parkedSweeper = ParkedTicketService(context: context, pos: pos)
    }

    override func tearDownWithError() throws {
        pos = nil; products = nil; inventory = nil; parkedSweeper = nil
        context = nil; container = nil
    }

    private func seed(barcode: String, price: Int64 = 1000, stock: Int32 = 20,
                      taxable: Bool = false) throws -> ProductSKU {
        let actor = makeUser(role: .contentManager)
        let spu = try products.createSPU(name: "P-\(barcode)", description: nil,
                                         category: nil, actor: actor)
        let sku = try products.createSKU(spuID: spu.id, barcode: barcode, stemCount: 0,
                                         wrapType: nil, color: nil, priceCents: price,
                                         isTaxable: taxable, actor: actor)
        _ = try inventory.adjustStock(skuID: sku.id, quantity: stock, reason: "seed", actorID: actor.id)
        return sku
    }

    private func makeCoupon(code: String, percent: Int64 = 10) {
        let rule = PriceRule(context: context)
        rule.id = UUID(); rule.name = "R"
        rule.discountType = DiscountType.percent.rawValue
        rule.discountValue = percent
        rule.appliesTo = DiscountAppliesTo.order.rawValue
        rule.maxDiscountPercent = 30
        rule.isActive = true
        rule.version = 0
        let c = Coupon(context: context)
        c.id = UUID(); c.code = code
        c.validFrom = Date().addingTimeInterval(-60)
        c.validTo   = Date().addingTimeInterval(3600)
        c.maxUses = 10; c.currentUses = 0; c.version = 0
        c.priceRule = rule
        try? context.save()
    }

    private func makeUser(role: Role) -> User {
        let u = User(context: context)
        u.id = UUID(); u.username = "\(role.rawValue)-\(UUID().uuidString.prefix(5))"
        u.role = role.rawValue; u.status = UserStatus.active.rawValue
        u.version = 0; u.createdAt = Date()
        return u
    }

    // MARK: - Happy path: scan → cart → discount → coupon → split → complete

    func test_happyPath_completesAndDecrementsInventory() throws {
        let sku = try seed(barcode: "HP-1", price: 1000, stock: 10)
        makeCoupon(code: "SPRING10", percent: 10)

        let order = try pos.createOrder(cashier: makeUser(role: .cashier))
        // Scan by resolving barcode → SKU, then adding to cart.
        let resolved = try pos.scanBarcode("HP-1")
        XCTAssertEqual(resolved.id, sku.id)
        let line = try pos.addToCart(orderID: order.id, skuID: sku.id, quantity: 2)

        try pos.applyItemDiscount(lineItemID: line.id, orderID: order.id, percent: 20)
        try pos.applyCoupon(orderID: order.id, code: "SPRING10")

        let totals = try pos.calculateTotals(orderID: order.id)
        // 2×1000 = 2000, item discount 20% = 400, line total 1600.
        // Order discount 10% of subtotal 1600 = 160, total = 1440.
        XCTAssertEqual(totals.subtotal, 1600)
        XCTAssertEqual(totals.discount, 160)
        XCTAssertEqual(totals.total, 1440)

        try pos.splitTender(orderID: order.id, payments: [
            .init(tender: .cash, amountCents: 1000, memo: nil),
            .init(tender: .cardOnFile, amountCents: 440, memo: "Visa 4242"),
        ])
        try pos.completeOrder(orderID: order.id, actor: makeUser(role: .cashier))
        XCTAssertEqual(order.status, OrderStatus.completed.rawValue)

        // Inventory: was 10, sold 2 → 8 on hand, 0 reserved.
        let avail = try inventory.getAvailable(skuID: sku.id)
        XCTAssertEqual(avail, 8)
    }

    // MARK: - Park → auto-expire → inventory unreserved

    func test_parkedOrder_autoExpires_andUnreservesInventory() throws {
        let sku = try seed(barcode: "PK-1", stock: 5)
        let order = try pos.createOrder(cashier: makeUser(role: .cashier))
        _ = try pos.addToCart(orderID: order.id, skuID: sku.id, quantity: 3)
        XCTAssertEqual(try inventory.getAvailable(skuID: sku.id), 2)

        try pos.parkOrder(orderID: order.id, actor: makeUser(role: .cashier))
        // Pretend 31 minutes have passed.
        order.parkedAt = Date().addingTimeInterval(-31 * 60)
        try context.save()
        let expired = try parkedSweeper.checkExpired()
        XCTAssertEqual(expired.count, 1)
        XCTAssertEqual(order.status, OrderStatus.voided.rawValue)
        XCTAssertEqual(try inventory.getAvailable(skuID: sku.id), 5)
    }

    // MARK: - Returns within / past window

    private func completedOrder(daysAgo: Int) throws -> (Order, ProductSKU) {
        let sku = try seed(barcode: "RT-\(daysAgo)", price: 1000, stock: 10)
        let order = try pos.createOrder(cashier: makeUser(role: .cashier))
        _ = try pos.addToCart(orderID: order.id, skuID: sku.id, quantity: 2)
        _ = try pos.calculateTotals(orderID: order.id)
        try pos.splitTender(orderID: order.id, payments: [
            .init(tender: .cash, amountCents: order.totalCents, memo: nil),
        ])
        try pos.completeOrder(orderID: order.id, actor: makeUser(role: .cashier))
        // Backdate completion.
        order.completedAt = Date().addingTimeInterval(TimeInterval(-daysAgo * 86400))
        try context.save()
        return (order, sku)
    }

    func test_return_withinWindow_succeeds_andRestoresInventory() throws {
        let (order, sku) = try completedOrder(daysAgo: 5)
        let lineID = order.lineItemsArray[0].id
        let availBefore = try inventory.getAvailable(skuID: sku.id)

        let ret = try pos.processReturn(
            originalOrderNumber: order.orderNumber,
            items: [.init(originalLineItemID: lineID, quantity: 2)],
            actorID: UUID()
        )
        XCTAssertEqual(ret.status, OrderStatus.returned.rawValue)
        XCTAssertLessThan(ret.totalCents, 0)
        XCTAssertEqual(order.status, OrderStatus.returned.rawValue)

        XCTAssertEqual(try inventory.getAvailable(skuID: sku.id), availBefore + 2)
    }

    func test_return_past30Days_blocked() throws {
        let (order, _) = try completedOrder(daysAgo: 31)
        let lineID = order.lineItemsArray[0].id
        XCTAssertThrowsError(
            try pos.processReturn(
                originalOrderNumber: order.orderNumber,
                items: [.init(originalLineItemID: lineID, quantity: 1)],
                actorID: UUID()
            )
        ) { err in
            if case POSError.returnPeriodExpired = err { } else {
                XCTFail("expected returnPeriodExpired, got \(err)")
            }
        }
    }

    // MARK: - Discount > 30% rejected (order-level)

    func test_orderDiscount_over30_rejected() throws {
        let order = try pos.createOrder(cashier: makeUser(role: .cashier))
        XCTAssertThrowsError(try pos.applyOrderDiscount(orderID: order.id, percent: 45))
    }

    // MARK: - Invalid coupon rejected

    func test_invalidCoupon_rejected() throws {
        let order = try pos.createOrder(cashier: makeUser(role: .cashier))
        XCTAssertThrowsError(try pos.applyCoupon(orderID: order.id, code: "FAKE"))
    }

    // MARK: - Shift close summary

    func test_shiftClose_generatesSummaryFile() throws {
        let (_, _) = try completedOrder(daysAgo: 0)
        let close = ShiftCloseService(context: context)
        let (summary, url) = try close.closeShift(cashierID: UUID(), day: Date())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan(summary.salesCents, 0)
        XCTAssertGreaterThanOrEqual(summary.orderCount, 1)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Authorization negative tests (Finding 2 & 4)

    func test_createOrder_withoutCashierRole_throwsInsufficientPermissions() throws {
        let reviewer = makeUser(role: .reviewer)
        XCTAssertThrowsError(try pos.createOrder(cashier: reviewer)) { err in
            if case AuthError.insufficientPermissions = err { } else {
                XCTFail("expected insufficientPermissions, got \(err)")
            }
        }
    }

    func test_createOrder_cashierRole_succeeds() throws {
        let cashier = makeUser(role: .cashier)
        XCTAssertNoThrow(try pos.createOrder(cashier: cashier))
    }
}
