import XCTest
import CoreData
@testable import GreenGate

/// Direct repository-layer tests. Each repository is exercised against an
/// in-memory store: insert → fetch → predicate-filtered fetch → uniqueness
/// / dedup paths.
final class RepositoryTests: XCTestCase {

    var container: NSPersistentContainer!
    var ctx: NSManagedObjectContext!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "store")
        container.loadPersistentStores { _, err in XCTAssertNil(err); exp.fulfill() }
        waitForExpectations(timeout: 5)
        ctx = container.viewContext
    }

    override func tearDownWithError() throws {
        ctx = nil; container = nil
    }

    // MARK: - ProductRepository

    func test_productRepo_insertSPU_andFetch() throws {
        let r = ProductRepository(context: ctx)
        let spu = r.insertSPU(name: "Rose", description: "red", category: "Flowers")
        try ctx.save()
        XCTAssertEqual(try r.fetchSPU(id: spu.id)?.name, "Rose")
        XCTAssertEqual(try r.fetchAllSPUs().count, 1)
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.draft.rawValue)
    }

    func test_productRepo_fetchSPUsByStatus_filters() throws {
        let r = ProductRepository(context: ctx)
        let a = r.insertSPU(name: "A", description: nil, category: nil)
        let b = r.insertSPU(name: "B", description: nil, category: nil)
        a.listingStatus = ProductListingStatus.listed.rawValue
        b.listingStatus = ProductListingStatus.draft.rawValue
        try ctx.save()
        let listed = try r.fetchSPUs(status: .listed)
        XCTAssertEqual(listed.map(\.name), ["A"])
    }

    func test_productRepo_barcodeExists_excludingSelf() throws {
        let r = ProductRepository(context: ctx)
        let spu = r.insertSPU(name: "X", description: nil, category: nil)
        let sku = r.insertSKU(spu: spu, barcode: "BC-1", stemCount: 1, wrapType: nil,
                              color: nil, priceCents: 100, isTaxable: true)
        try ctx.save()
        XCTAssertTrue(try r.barcodeExists("BC-1"))
        XCTAssertFalse(try r.barcodeExists("BC-1", excludingSKU: sku.id),
                       "Excluding the SKU's own id should report it as not-existing")
    }

    func test_productRepo_fetchSKUByBarcode() throws {
        let r = ProductRepository(context: ctx)
        let spu = r.insertSPU(name: "X", description: nil, category: nil)
        _ = r.insertSKU(spu: spu, barcode: "FIND-ME", stemCount: 1, wrapType: nil,
                        color: nil, priceCents: 100, isTaxable: true)
        try ctx.save()
        XCTAssertNotNil(try r.fetchSKU(barcode: "FIND-ME"))
        XCTAssertNil(try r.fetchSKU(barcode: "MISSING"))
    }

    // MARK: - InventoryRepository

    func test_inventoryRepo_ensureLot_createsWhenMissing() throws {
        let prod = ProductRepository(context: ctx)
        let inv  = InventoryRepository(context: ctx)
        let spu = prod.insertSPU(name: "X", description: nil, category: nil)
        let sku = prod.insertSKU(spu: spu, barcode: "BC", stemCount: 0, wrapType: nil,
                                 color: nil, priceCents: 100, isTaxable: true)
        try ctx.save()
        XCTAssertNil(inv.primaryLot(for: sku))
        let lot = inv.ensureLot(for: sku)
        try ctx.save()
        XCTAssertEqual(lot.sku?.id, sku.id)
        XCTAssertNotNil(inv.primaryLot(for: sku))
    }

    func test_inventoryRepo_lowStockThreshold_filters() throws {
        let prod = ProductRepository(context: ctx)
        let inv  = InventoryRepository(context: ctx)
        let spu = prod.insertSPU(name: "X", description: nil, category: nil)
        let low = prod.insertSKU(spu: spu, barcode: "L", stemCount: 0, wrapType: nil,
                                 color: nil, priceCents: 100, isTaxable: true)
        let ok  = prod.insertSKU(spu: spu, barcode: "O", stemCount: 0, wrapType: nil,
                                 color: nil, priceCents: 100, isTaxable: true)
        let lowLot = inv.ensureLot(for: low); lowLot.onHand = 3
        let okLot  = inv.ensureLot(for: ok);  okLot.onHand  = 100
        try ctx.save()
        let result = try inv.fetchLowStockSKUs(threshold: 10)
        XCTAssertTrue(result.contains { $0.id == low.id })
        XCTAssertFalse(result.contains { $0.id == ok.id })
    }

    // MARK: - OrderRepository

    func test_orderRepo_insertOrder_andFetchByNumber() throws {
        let r = OrderRepository(context: ctx)
        let o = r.insertOrder(cashier: nil, orderNumber: "GG-20260101-0001")
        try ctx.save()
        XCTAssertEqual(try r.fetch(orderNumber: "GG-20260101-0001")?.id, o.id)
        XCTAssertNil(try r.fetch(orderNumber: "GG-20260101-9999"))
    }

    func test_orderRepo_fetchParked_excludesOpen() throws {
        let r = OrderRepository(context: ctx)
        let p = r.insertOrder(cashier: nil, orderNumber: "P-1")
        let o = r.insertOrder(cashier: nil, orderNumber: "O-1")
        p.status = OrderStatus.parked.rawValue
        p.parkedAt = Date()
        o.status = OrderStatus.open.rawValue
        try ctx.save()
        let parked = try r.fetchParked()
        XCTAssertEqual(parked.map(\.orderNumber), ["P-1"])
    }

    func test_orderRepo_countOrdersForToday() throws {
        let r = OrderRepository(context: ctx)
        _ = r.insertOrder(cashier: nil, orderNumber: "A")
        _ = r.insertOrder(cashier: nil, orderNumber: "B")
        try ctx.save()
        XCTAssertEqual(try r.countOrders(on: Date()), 2)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertEqual(try r.countOrders(on: yesterday), 0)
    }

    func test_orderRepo_fetchCompletedInRange_includesReturns() throws {
        let r = OrderRepository(context: ctx)
        let now = Date()
        let day = Calendar.current.startOfDay(for: now)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let completed = r.insertOrder(cashier: nil, orderNumber: "C-1")
        completed.status = OrderStatus.completed.rawValue
        completed.completedAt = now
        let returned = r.insertOrder(cashier: nil, orderNumber: "R-1")
        returned.status = OrderStatus.returned.rawValue
        returned.completedAt = now
        let voided = r.insertOrder(cashier: nil, orderNumber: "V-1")
        voided.status = OrderStatus.voided.rawValue
        voided.completedAt = now
        try ctx.save()
        let inRange = try r.fetchCompleted(in: day...endOfDay)
        let numbers = Set(inRange.map(\.orderNumber))
        XCTAssertEqual(numbers, ["C-1", "R-1"], "VOIDED orders excluded from shift summary")
    }

    // MARK: - CouponRepository

    func test_couponRepo_fetchByCode_caseInsensitive() throws {
        let c = Coupon(context: ctx)
        c.id = UUID(); c.code = "Spring10"
        c.validFrom = Date(); c.validTo = Date().addingTimeInterval(3600)
        c.maxUses = 5; c.currentUses = 0; c.version = 0
        try ctx.save()
        let r = CouponRepository(context: ctx)
        XCTAssertEqual(try r.fetch(code: "spring10")?.code, "Spring10")
        XCTAssertEqual(try r.fetch(code: "SPRING10")?.code, "Spring10")
        XCTAssertNil(try r.fetch(code: "OTHER"))
    }

    func test_couponRepo_fetchAll_sortedByCode() throws {
        for code in ["B", "A", "C"] {
            let c = Coupon(context: ctx)
            c.id = UUID(); c.code = code
            c.validFrom = Date(); c.validTo = Date().addingTimeInterval(3600)
            c.maxUses = 1; c.currentUses = 0; c.version = 0
        }
        try ctx.save()
        XCTAssertEqual(try CouponRepository(context: ctx).fetchAll().map(\.code), ["A", "B", "C"])
    }

    // MARK: - TicketRepository

    func test_ticketRepo_insertEvent_andTickets_andFetchByNumber() throws {
        let r = TicketRepository(context: ctx)
        let event = r.insertEvent(name: "E", venue: nil, eventDate: Date(),
                                   doorOpen: Date(),
                                   doorClose: Date().addingTimeInterval(3600),
                                   capacity: 10)
        let ticket = r.insertTicket(event: event, holderName: nil,
                                    ticketNumber: "T-001", qrPayload: "p",
                                    signature: "s",
                                    validFrom: event.doorOpenTime,
                                    validTo: event.doorCloseTime)
        try ctx.save()
        XCTAssertEqual(try r.fetchTicket(number: "T-001")?.id, ticket.id)
        XCTAssertEqual(try r.fetchAllEvents().count, 1)
    }

    func test_ticketRepo_validTicketsPastNow() throws {
        let r = TicketRepository(context: ctx)
        let past = r.insertEvent(name: "Past", venue: nil, eventDate: Date(),
                                 doorOpen: Date().addingTimeInterval(-7200),
                                 doorClose: Date().addingTimeInterval(-3600),
                                 capacity: 5)
        let live = r.insertEvent(name: "Live", venue: nil, eventDate: Date(),
                                 doorOpen: Date().addingTimeInterval(-300),
                                 doorClose: Date().addingTimeInterval(3600),
                                 capacity: 5)
        _ = r.insertTicket(event: past, holderName: nil, ticketNumber: "OLD",
                           qrPayload: "p", signature: "s",
                           validFrom: past.doorOpenTime, validTo: past.doorCloseTime)
        _ = r.insertTicket(event: live, holderName: nil, ticketNumber: "NEW",
                           qrPayload: "p", signature: "s",
                           validFrom: live.doorOpenTime, validTo: live.doorCloseTime)
        try ctx.save()
        let stale = try r.fetchValidTicketsPast(Date())
        XCTAssertEqual(stale.map(\.ticketNumber), ["OLD"])
    }

    // MARK: - PropertyRepository

    func test_propertyRepo_insert_andChangeHistory() throws {
        let r = PropertyRepository(context: ctx)
        let l = r.insert(title: "L", line1: "1 St", line2: nil, city: "SF",
                         state: "CA", zip: "94107", sqft: 600,
                         amenitiesJSON: nil, rentCents: 200000, depositCents: 200000,
                         leaseMonths: 12, availableFrom: Date(),
                         createdBy: nil)
        let h = r.insertChange(listing: l, field: "rent",
                               oldValue: "200000", newValue: "250000", actor: nil)
        try ctx.save()
        XCTAssertEqual(try r.fetch(id: l.id)?.title, "L")
        XCTAssertEqual(l.changeHistoryArray.count, 1)
        XCTAssertEqual(h.fieldName, "rent")
    }

    // MARK: - AttachmentRepository

    func test_attachmentRepo_dedupByChecksum() throws {
        let parent = UUID()
        let a = Attachment(context: ctx)
        a.id = UUID(); a.parentType = AttachmentParentType.product.rawValue
        a.parentID = parent; a.fileName = "x.jpg"; a.filePath = "p/x.jpg"
        a.fileSizeBytes = 1; a.mimeType = AttachmentMimeType.jpeg.rawValue
        a.checksumSHA256 = "deadbeef"; a.isCompressed = true; a.createdAt = Date()
        try ctx.save()
        let r = AttachmentRepository(context: ctx)
        XCTAssertNotNil(try r.fetchByChecksum("deadbeef", parentType: .product, parentID: parent))
        XCTAssertNil(try r.fetchByChecksum("deadbeef", parentType: .product, parentID: UUID()),
                     "Different parent must NOT match — dedup is scoped per parent")
    }

    func test_attachmentRepo_fetchByParent_sortedNewestFirst() throws {
        let parent = UUID()
        for i in 0..<3 {
            let a = Attachment(context: ctx)
            a.id = UUID(); a.parentType = AttachmentParentType.property.rawValue
            a.parentID = parent; a.fileName = "f\(i).jpg"; a.filePath = "p/\(i).jpg"
            a.fileSizeBytes = 1; a.mimeType = AttachmentMimeType.jpeg.rawValue
            a.checksumSHA256 = "h\(i)"; a.isCompressed = false
            a.createdAt = Date().addingTimeInterval(TimeInterval(i))
        }
        try ctx.save()
        let result = try AttachmentRepository(context: ctx)
            .fetch(parentType: .property, parentID: parent)
        XCTAssertEqual(result.map(\.fileName), ["f2.jpg", "f1.jpg", "f0.jpg"])
    }
}
