import XCTest
import CoreData
@testable import GreenGate

/// Unit tests for POSService: discount caps, coupon validation, order-number
/// format, and tax/rounding. In-memory Core Data store.
final class POSServiceTests: XCTestCase {

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

    private func makeCashier() -> User {
        let u = User(context: context)
        u.id = UUID()
        u.username = "cashier-\(UUID().uuidString.prefix(6))"
        u.role = Role.cashier.rawValue
        u.status = UserStatus.active.rawValue
        u.version = 0
        u.createdAt = Date()
        return u
    }

    private func makeReviewer() -> User {
        let u = User(context: context)
        u.id = UUID()
        u.username = "reviewer-\(UUID().uuidString.prefix(6))"
        u.role = Role.reviewer.rawValue
        u.status = UserStatus.active.rawValue
        u.version = 0
        u.createdAt = Date()
        return u
    }

    private func makeContentManager() -> User {
        let u = User(context: context)
        u.id = UUID()
        u.username = "cm-\(UUID().uuidString.prefix(6))"
        u.role = Role.contentManager.rawValue
        u.status = UserStatus.active.rawValue
        u.version = 0
        u.createdAt = Date()
        return u
    }

    private func seedSKU(barcode: String = "BC-\(UUID().uuidString.prefix(6))",
                         priceCents: Int64 = 1000,
                         taxable: Bool = true,
                         stock: Int32 = 50) throws -> ProductSKU {
        let actor = makeContentManager()
        let spu = try products.createSPU(name: "X", description: nil, category: nil, actor: actor)
        let sku = try products.createSKU(spuID: spu.id, barcode: barcode, stemCount: 1,
                                         wrapType: nil, color: nil, priceCents: priceCents,
                                         isTaxable: taxable, actor: actor)
        _ = try inventory.adjustStock(skuID: sku.id, quantity: stock, reason: "seed", actorID: actor.id)
        return sku
    }

    // MARK: - Order number format (POS-11)

    func test_orderNumber_followsFormat() throws {
        let n = try pos.generateOrderNumber(for: Date())
        let pattern = #"^GG-\d{8}-\d{4}$"#
        XCTAssertNotNil(n.range(of: pattern, options: .regularExpression),
                        "Expected GG-YYYYMMDD-NNNN, got \(n)")
    }

    func test_orderNumber_sequenceIncrementsPerDay() throws {
        _ = try pos.createOrder(cashier: makeCashier())
        _ = try pos.createOrder(cashier: makeCashier())
        let next = try pos.generateOrderNumber(for: Date())
        XCTAssertTrue(next.hasSuffix("-0003"), "Expected -0003 suffix, got \(next)")
    }

    // MARK: - Discount cap (POS-03)

    func test_itemDiscount_exceeds30Percent_rejected() throws {
        let sku = try seedSKU()
        let order = try pos.createOrder(cashier: makeCashier())
        let line = try pos.addToCart(orderID: order.id, skuID: sku.id, quantity: 2)
        XCTAssertThrowsError(
            try pos.applyItemDiscount(lineItemID: line.id, orderID: order.id, percent: 31)
        )
    }

    func test_itemDiscount_at30Percent_accepted() throws {
        let sku = try seedSKU(priceCents: 1000)
        let order = try pos.createOrder(cashier: makeCashier())
        let line = try pos.addToCart(orderID: order.id, skuID: sku.id, quantity: 2)
        try pos.applyItemDiscount(lineItemID: line.id, orderID: order.id, percent: 30)
        XCTAssertEqual(line.discountCents, 600) // 30% of 2000
        XCTAssertEqual(line.lineTotalCents, 1400)
    }

    // MARK: - Order-level discount cap (POS-04)

    func test_orderDiscount_exceedsCap_rejected() throws {
        let order = try pos.createOrder(cashier: makeCashier())
        XCTAssertThrowsError(try pos.applyOrderDiscount(orderID: order.id, percent: 31))
    }

    // MARK: - Coupon validation (POS-06)

    private func makeCoupon(code: String, validFrom: Date, validTo: Date,
                            maxUses: Int32 = 10, currentUses: Int32 = 0,
                            discountPercent: Int64 = 10) -> Coupon {
        let rule = PriceRule(context: context)
        rule.id = UUID()
        rule.name = "Rule"
        rule.discountType = DiscountType.percent.rawValue
        rule.discountValue = discountPercent
        rule.appliesTo = DiscountAppliesTo.order.rawValue
        rule.maxDiscountPercent = 30
        rule.isActive = true
        rule.version = 0

        let c = Coupon(context: context)
        c.id = UUID()
        c.code = code
        c.validFrom = validFrom
        c.validTo = validTo
        c.maxUses = maxUses
        c.currentUses = currentUses
        c.version = 0
        c.priceRule = rule
        try? context.save()
        return c
    }

    func test_coupon_expired_rejected() throws {
        let order = try pos.createOrder(cashier: makeCashier())
        let past = Date().addingTimeInterval(-86400)
        _ = makeCoupon(code: "EXP", validFrom: past.addingTimeInterval(-86400), validTo: past)
        XCTAssertThrowsError(try pos.applyCoupon(orderID: order.id, code: "EXP")) { err in
            if case POSError.couponExpired = err { } else { XCTFail("expected couponExpired, got \(err)") }
        }
    }

    func test_coupon_notYetValid_rejected() throws {
        let order = try pos.createOrder(cashier: makeCashier())
        let future = Date().addingTimeInterval(86400)
        _ = makeCoupon(code: "FUTURE", validFrom: future, validTo: future.addingTimeInterval(86400))
        XCTAssertThrowsError(try pos.applyCoupon(orderID: order.id, code: "FUTURE"))
    }

    func test_coupon_exhausted_rejected() throws {
        let order = try pos.createOrder(cashier: makeCashier())
        _ = makeCoupon(code: "USED", validFrom: Date().addingTimeInterval(-60),
                       validTo: Date().addingTimeInterval(3600), maxUses: 1, currentUses: 1)
        XCTAssertThrowsError(try pos.applyCoupon(orderID: order.id, code: "USED"))
    }

    func test_coupon_notFound_rejected() throws {
        let order = try pos.createOrder(cashier: makeCashier())
        XCTAssertThrowsError(try pos.applyCoupon(orderID: order.id, code: "NOPE"))
    }

    func test_coupon_valid_applied() throws {
        let order = try pos.createOrder(cashier: makeCashier())
        let sku = try seedSKU(priceCents: 1000)
        _ = try pos.addToCart(orderID: order.id, skuID: sku.id, quantity: 1)
        _ = makeCoupon(code: "SPRING", validFrom: Date().addingTimeInterval(-60),
                       validTo: Date().addingTimeInterval(3600), discountPercent: 10)
        try pos.applyCoupon(orderID: order.id, code: "SPRING")
        XCTAssertEqual(order.orderDiscountPercent, 10)
        XCTAssertEqual(order.couponCode, "SPRING")
    }

    // MARK: - Cash rounding (POS-07) — delegated to CurrencyFormatter (banker's)

    func test_taxRounding_usesBankers() {
        // 8.875% of $10.00 = 88.75¢ → rounds to 89 (not halfway; 88.75 > 88.5).
        XCTAssertEqual(CurrencyFormatter.taxCents(onSubtotal: 1000, rateBasisPoints: 88750), 89)
        // 8.875% of $20.00 = 177.5¢ — exact halfway, banker's → 178 (even).
        XCTAssertEqual(CurrencyFormatter.taxCents(onSubtotal: 2000, rateBasisPoints: 88750), 178)
        // 8.875% of $60.00 = 532.5¢ — exact halfway, banker's → 532 (even).
        XCTAssertEqual(CurrencyFormatter.taxCents(onSubtotal: 6000, rateBasisPoints: 88750), 532)
    }

    // MARK: - Split tender mismatch (POS-08)

    func test_splitTender_mismatch_throws() throws {
        let sku = try seedSKU(priceCents: 1000, taxable: false)
        let order = try pos.createOrder(cashier: makeCashier())
        _ = try pos.addToCart(orderID: order.id, skuID: sku.id, quantity: 1)
        _ = try pos.calculateTotals(orderID: order.id)

        XCTAssertThrowsError(try pos.splitTender(orderID: order.id, payments: [
            .init(tender: .cash, amountCents: 500, memo: nil),
            .init(tender: .cardOnFile, amountCents: 400, memo: "card"),
        ])) { err in
            if case POSError.splitTenderMismatch = err { } else {
                XCTFail("expected splitTenderMismatch, got \(err)")
            }
        }
    }

    func test_splitTender_exactMatch_succeeds() throws {
        let sku = try seedSKU(priceCents: 5000, taxable: false)
        let order = try pos.createOrder(cashier: makeCashier())
        _ = try pos.addToCart(orderID: order.id, skuID: sku.id, quantity: 1)
        _ = try pos.calculateTotals(orderID: order.id)
        try pos.splitTender(orderID: order.id, payments: [
            .init(tender: .cash, amountCents: 3000, memo: nil),
            .init(tender: .cardOnFile, amountCents: 2000, memo: "Visa"),
        ])
        XCTAssertEqual(order.paymentsArray.count, 2)
    }

    // MARK: - Tax calculation (PROD-04)

    func test_totals_includeTaxOnTaxableLinesOnly() throws {
        let taxed = try seedSKU(priceCents: 1000, taxable: true)
        let exempt = try seedSKU(priceCents: 1000, taxable: false)
        let order = try pos.createOrder(cashier: makeCashier())
        _ = try pos.addToCart(orderID: order.id, skuID: taxed.id, quantity: 1)
        _ = try pos.addToCart(orderID: order.id, skuID: exempt.id, quantity: 1)
        let t = try pos.calculateTotals(orderID: order.id)
        XCTAssertEqual(t.subtotal, 2000)
        // Only 1000 is taxable → 88.75¢ → 89 (normal rounding, not halfway).
        XCTAssertEqual(t.tax, 89)
        XCTAssertEqual(t.total, 2089)
    }

    // MARK: - Authorization negative tests (Finding 2)

    func test_createOrder_reviewerRole_throwsInsufficientPermissions() throws {
        let reviewer = makeReviewer()
        XCTAssertThrowsError(try pos.createOrder(cashier: reviewer)) { err in
            if case AuthError.insufficientPermissions = err { } else {
                XCTFail("expected insufficientPermissions, got \(err)")
            }
        }
    }

    func test_createOrder_cashierRole_succeeds() throws {
        let cashier = makeCashier()
        XCTAssertNoThrow(try pos.createOrder(cashier: cashier))
    }
}
