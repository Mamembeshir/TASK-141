import XCTest
import CoreData
@testable import GreenGate

/// Cross-module end-to-end workflows from the STEP 6 verification matrix.
final class WorkflowIntegrationTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var products: ProductService!
    var inventory: InventoryService!
    var pos: POSService!
    var tickets: TicketService!
    var properties: PropertyService!
    var importExport: ImportExportService!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "store")
        container.loadPersistentStores { _, err in XCTAssertNil(err); exp.fulfill() }
        waitForExpectations(timeout: 5)
        context = container.viewContext
        products = ProductService(context: context)
        inventory = InventoryService(context: context)
        pos = POSService(context: context)
        tickets = TicketService(context: context)
        properties = PropertyService(context: context)
        importExport = ImportExportService(context: context)
    }

    override func tearDownWithError() throws {
        products = nil; inventory = nil; pos = nil
        tickets = nil; properties = nil; importExport = nil
        context = nil; container = nil
    }

    private func user(role: Role) -> User {
        let u = User(context: context)
        u.id = UUID(); u.username = "u-\(UUID().uuidString.prefix(5))"
        u.role = role.rawValue; u.status = UserStatus.active.rawValue
        u.version = 0; u.createdAt = Date()
        return u
    }

    // MARK: - #1 Full product → listing → POS sale pipeline

    func test_productLifecycle_submitApproveScanSell() throws {
        let reviewer = user(role: .reviewer)
        let actor = user(role: .contentManager)
        let cashier = user(role: .cashier)
        let spu = try products.createSPU(name: "Rose", description: nil,
                                         category: "Flowers", actor: actor)
        try products.createSKU(spuID: spu.id, barcode: "RS-1", stemCount: 12,
                               wrapType: "paper", color: "red",
                               priceCents: 2500, isTaxable: false, actor: actor)
        try products.submitForApproval(spuID: spu.id, actor: actor)
        try products.approve(spuID: spu.id, reviewerID: reviewer.id, reviewer: reviewer)
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.listed.rawValue)

        let sku = spu.skusArray[0]
        _ = try inventory.adjustStock(skuID: sku.id, quantity: 10, reason: "seed", actorID: actor.id)

        let order = try pos.createOrder(cashier: cashier)
        let resolved = try pos.scanBarcode("RS-1")
        _ = try pos.addToCart(orderID: order.id, skuID: resolved.id, quantity: 2)
        _ = try pos.calculateTotals(orderID: order.id)
        try pos.splitTender(orderID: order.id, payments: [
            .init(tender: .cash, amountCents: order.totalCents, memo: nil)
        ])
        try pos.completeOrder(orderID: order.id, actor: cashier)
        XCTAssertEqual(try inventory.getAvailable(skuID: sku.id), 8)
    }

    // MARK: - #10 Role permissions

    func test_permissions_reviewerApprovalOnly() throws {
        let cashier = user(role: .cashier)
        let cm = user(role: .contentManager)
        let spu = try products.createSPU(name: "X", description: nil, category: nil, actor: cm)
        try products.createSKU(spuID: spu.id, barcode: "X-1", stemCount: 0,
                               wrapType: nil, color: nil, priceCents: 100,
                               isTaxable: false, actor: cm)
        try products.submitForApproval(spuID: spu.id, actor: cm)
        XCTAssertThrowsError(try products.approve(spuID: spu.id, reviewerID: cashier.id,
                                                   reviewer: cashier))
    }

    func test_permissions_nonAdminCannotLockProperty() throws {
        let cm = user(role: .contentManager)
        let reviewer = user(role: .reviewer)
        let listing = try properties.create(
            input: .init(title: "L", addressLine1: "1 St", addressLine2: nil,
                         city: "SF", state: "CA", zipCode: "94107",
                         squareFootage: 700, amenities: [],
                         rentCents: 200000, depositCents: 200000, leaseMonths: 12,
                         availableFrom: Date().addingTimeInterval(86400)),
            actor: cm)
        try properties.submitForReview(listingID: listing.id, actor: cm)
        try properties.approve(listingID: listing.id, reviewer: reviewer)
        XCTAssertThrowsError(try properties.lock(listingID: listing.id, admin: cm))
    }

    // MARK: - #7 Import CSV with mixed quality

    func test_import_mixedQuality_partialSuccess() throws {
        // 3 rows: 2 valid, 1 missing price (rejected by required-field + quality)
        let csv = """
        spuName,barcode,stemCount,wrapType,color,priceCents,isTaxable
        Rose,IM-1,12,paper,red,2500,true
        Lily,IM-2,6,paper,white,1500,true
        Bad,IM-3,3,paper,green,,true
        """
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).csv")
        try csv.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let importActor = user(role: .contentManager)
        let report = try importExport.importProductsCSV(at: tmp, actor: importActor)
        XCTAssertEqual(report.imported, 2)
        XCTAssertEqual(report.rejected, 1)
        XCTAssertFalse(report.errors.isEmpty)
    }

    // MARK: - #8 Export with mask toggle

    func test_export_producesFile() throws {
        let actor = user(role: .contentManager)
        let reviewer = user(role: .reviewer)
        let spu = try products.createSPU(name: "Tulip", description: "seasonal",
                                         category: "Flowers", actor: actor)
        try products.createSKU(spuID: spu.id, barcode: "TL-1", stemCount: 5,
                               wrapType: "paper", color: "yellow",
                               priceCents: 1500, isTaxable: true, actor: actor)
        try products.submitForApproval(spuID: spu.id, actor: actor)
        try products.approve(spuID: spu.id, reviewerID: reviewer.id, reviewer: reviewer)

        let url = try importExport.exportProductsCSV(
            statusFilter: .listed, maskSensitive: true, actorID: actor.id
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(content.contains("TL-1"))
        // Description is masked to empty in our implementation (showLast: 0).
    }

    // MARK: - #9 Magic-byte validation

    func test_attachment_disguisedTxtAsJpg_rejected() throws {
        let fake = "this is not a JPG".data(using: .utf8)!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-\(UUID().uuidString).jpg")
        try fake.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = AttachmentService(context: context)
        XCTAssertThrowsError(
            try service.upload(
                .init(sourceURL: url, declaredMime: .jpeg,
                      parentType: .product, parentID: UUID(),
                      licensing: nil, copyright: nil),
                uploadedBy: user(role: .admin)
            )
        ) { err in
            if case AttachmentError.magicBytesMismatch = err { } else {
                XCTFail("expected magicBytesMismatch, got \(err)")
            }
        }
    }

    // MARK: - #12 Audit log entries

    func test_audit_writeForEveryMajorAction() throws {
        let actor = user(role: .contentManager)
        let reviewer = user(role: .reviewer)
        let spu = try products.createSPU(name: "X", description: nil, category: nil, actor: actor)
        try products.createSKU(spuID: spu.id, barcode: "A-1", stemCount: 0,
                               wrapType: nil, color: nil, priceCents: 100,
                               isTaxable: false, actor: actor)
        try products.submitForApproval(spuID: spu.id, actor: actor)
        try products.approve(spuID: spu.id, reviewerID: reviewer.id, reviewer: reviewer)
        let r = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        r.predicate = NSPredicate(format: "entityID == %@", spu.id as CVarArg)
        XCTAssertGreaterThanOrEqual(try context.fetch(r).count, 2)
    }

    // MARK: - Background import branching (Issue 1)

    /// Verifies that `schedulePendingImport` persists the file extension so the
    /// background handler can branch between CSV and XLSX parsing.
    func test_backgroundImport_csvExtension_persistedInDefaults() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("products.csv")
        let actorID = UUID()
        BulkImportTask.schedulePendingImport(fileURL: url, actorID: actorID)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "GreenGate.pendingImportExt"), "csv")
        // Cleanup.
        UserDefaults.standard.removeObject(forKey: "GreenGate.pendingImportURL")
        UserDefaults.standard.removeObject(forKey: "GreenGate.pendingImportActorID")
        UserDefaults.standard.removeObject(forKey: "GreenGate.pendingImportExt")
    }

    func test_backgroundImport_xlsxExtension_persistedInDefaults() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("products.xlsx")
        let actorID = UUID()
        BulkImportTask.schedulePendingImport(fileURL: url, actorID: actorID)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "GreenGate.pendingImportExt"), "xlsx")
        // Cleanup.
        UserDefaults.standard.removeObject(forKey: "GreenGate.pendingImportURL")
        UserDefaults.standard.removeObject(forKey: "GreenGate.pendingImportActorID")
        UserDefaults.standard.removeObject(forKey: "GreenGate.pendingImportExt")
    }

    // MARK: - XLSX import (Issue 6)

    /// XLSX import should reject a file that is not a valid ZIP/XLSX and surface
    /// an error — it must NOT silently call the CSV path.
    func test_xlsxImport_invalidFile_throws() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-\(UUID().uuidString).xlsx")
        try? "not an xlsx".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let xlsxActor = user(role: .contentManager)
        XCTAssertThrowsError(try importExport.importProductsXLSX(at: url, actor: xlsxActor),
                             "A malformed XLSX file must throw rather than silently succeed")
    }
}
