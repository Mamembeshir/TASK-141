import XCTest
import CoreData
@testable import GreenGate

/// State-machine and barcode-uniqueness unit tests for ProductService.
/// Uses an in-memory Core Data stack.
final class ProductServiceTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var service: ProductService!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "store")
        container.loadPersistentStores { _, err in XCTAssertNil(err); exp.fulfill() }
        waitForExpectations(timeout: 5)
        context = container.viewContext
        service = ProductService(context: context)
    }

    override func tearDownWithError() throws {
        service = nil
        context = nil
        container = nil
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

    private func makeCashier() -> User {
        let u = User(context: context)
        u.id = UUID()
        u.username = "cash-\(UUID().uuidString.prefix(6))"
        u.role = Role.cashier.rawValue
        u.status = UserStatus.active.rawValue
        u.version = 0
        u.createdAt = Date()
        return u
    }

    private func seedSPUWithSKU(barcode: String = "BC-\(UUID().uuidString.prefix(6))") throws -> ProductSPU {
        let actor = makeContentManager()
        let spu = try service.createSPU(name: "Spring Bouquet", description: nil,
                                        category: "Flowers", actor: actor)
        try service.createSKU(spuID: spu.id, barcode: barcode, stemCount: 12,
                              wrapType: "paper", color: "pink",
                              priceCents: 2500, isTaxable: true, actor: actor)
        return spu
    }

    // MARK: - Creation

    func test_createSPU_isDraft() throws {
        let spu = try service.createSPU(name: "Test", description: nil, category: nil,
                                        actor: makeContentManager())
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.draft.rawValue)
        XCTAssertFalse(spu.isListed)
    }

    func test_createSPU_emptyName_throws() {
        XCTAssertThrowsError(
            try service.createSPU(name: "   ", description: nil, category: nil,
                                  actor: makeContentManager())
        )
    }

    // MARK: - Barcode uniqueness (PROD-02)

    func test_createSKU_duplicateBarcode_throws() throws {
        let cm = makeContentManager()
        let spu = try seedSPUWithSKU(barcode: "DUP-1")
        XCTAssertThrowsError(
            try service.createSKU(spuID: spu.id, barcode: "DUP-1", stemCount: 6,
                                  wrapType: nil, color: nil, priceCents: 1000,
                                  isTaxable: true, actor: cm)
        ) { err in
            if case ProductError.duplicateBarcode = err { } else {
                XCTFail("expected duplicateBarcode, got \(err)")
            }
        }
    }

    func test_createSKU_emptyBarcode_throws() throws {
        let cm = makeContentManager()
        let spu = try service.createSPU(name: "X", description: nil, category: nil, actor: cm)
        XCTAssertThrowsError(
            try service.createSKU(spuID: spu.id, barcode: "  ", stemCount: 0,
                                  wrapType: nil, color: nil, priceCents: 0,
                                  isTaxable: false, actor: cm)
        )
    }

    // MARK: - Listing state machine (PRD 9.1)

    func test_submit_draftWithoutSKU_throws() throws {
        let cm = makeContentManager()
        let spu = try service.createSPU(name: "Empty", description: nil, category: nil, actor: cm)
        XCTAssertThrowsError(try service.submitForApproval(spuID: spu.id, actor: cm)) { err in
            if case ProductError.skuRequiredForApproval = err { } else {
                XCTFail("expected skuRequiredForApproval, got \(err)")
            }
        }
    }

    func test_submit_draftWithSKU_transitionsToPending() throws {
        let cm = makeContentManager()
        let spu = try seedSPUWithSKU()
        try service.submitForApproval(spuID: spu.id, actor: cm)
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.pendingApproval.rawValue)
    }

    func test_approve_fromPending_transitionsToListed() throws {
        let cm = makeContentManager()
        let reviewer = makeReviewer()
        let spu = try seedSPUWithSKU()
        try service.submitForApproval(spuID: spu.id, actor: cm)
        try service.approve(spuID: spu.id, reviewerID: reviewer.id, reviewer: reviewer)
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.listed.rawValue)
        XCTAssertTrue(spu.isListed)
        XCTAssertEqual(spu.reviewerID, reviewer.id)
    }

    func test_approve_byNonReviewer_throws() throws {
        let cm = makeContentManager()
        let cashier = makeCashier()
        let spu = try seedSPUWithSKU()
        try service.submitForApproval(spuID: spu.id, actor: cm)
        XCTAssertThrowsError(
            try service.approve(spuID: spu.id, reviewerID: cashier.id, reviewer: cashier)
        )
    }

    func test_reject_fromPending_returnsToDraftWithNotes() throws {
        let cm = makeContentManager()
        let reviewer = makeReviewer()
        let spu = try seedSPUWithSKU()
        try service.submitForApproval(spuID: spu.id, actor: cm)
        try service.reject(spuID: spu.id, reviewerID: reviewer.id, reviewer: reviewer,
                           notes: "Pricing too high")
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.draft.rawValue)
        XCTAssertEqual(spu.rejectionNotes, "Pricing too high")
    }

    func test_reject_requiresNotes() throws {
        let cm = makeContentManager()
        let reviewer = makeReviewer()
        let spu = try seedSPUWithSKU()
        try service.submitForApproval(spuID: spu.id, actor: cm)
        XCTAssertThrowsError(
            try service.reject(spuID: spu.id, reviewerID: reviewer.id, reviewer: reviewer, notes: "")
        )
    }

    func test_approve_fromDraft_throws() throws {
        let reviewer = makeReviewer()
        let spu = try seedSPUWithSKU()
        XCTAssertThrowsError(
            try service.approve(spuID: spu.id, reviewerID: reviewer.id, reviewer: reviewer)
        )
    }

    // MARK: - Delist flow

    func test_requestDelist_fromListed_transitionsToPending() throws {
        let cm = makeContentManager()
        let reviewer = makeReviewer()
        let spu = try seedSPUWithSKU()
        try service.submitForApproval(spuID: spu.id, actor: cm)
        try service.approve(spuID: spu.id, reviewerID: reviewer.id, reviewer: reviewer)
        try service.requestDelist(spuID: spu.id, actor: cm)
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.pendingApproval.rawValue)
        XCTAssertTrue(spu.pendingDelist)
    }

    func test_approveDelist_transitionsToDelisted() throws {
        let cm = makeContentManager()
        let reviewer = makeReviewer()
        let spu = try seedSPUWithSKU()
        try service.submitForApproval(spuID: spu.id, actor: cm)
        try service.approve(spuID: spu.id, reviewerID: reviewer.id, reviewer: reviewer)
        try service.requestDelist(spuID: spu.id, actor: cm)
        try service.approveDelist(spuID: spu.id, reviewerID: reviewer.id, reviewer: reviewer)
        XCTAssertEqual(spu.listingStatus, ProductListingStatus.delisted.rawValue)
        XCTAssertFalse(spu.isListed)
        XCTAssertFalse(spu.pendingDelist)
    }

    func test_requestDelist_fromDraft_throws() throws {
        let cm = makeContentManager()
        let spu = try seedSPUWithSKU()
        XCTAssertThrowsError(try service.requestDelist(spuID: spu.id, actor: cm))
    }

    // MARK: - Authorization negative tests (Finding 1)

    func test_createSPU_cashierRole_throwsInsufficientPermissions() throws {
        let cashier = makeCashier()
        XCTAssertThrowsError(
            try service.createSPU(name: "Flower", description: nil, category: nil, actor: cashier)
        ) { err in
            if case ProductError.insufficientPermissions = err { } else {
                XCTFail("expected insufficientPermissions, got \(err)")
            }
        }
    }

    func test_submitForApproval_cashierRole_throwsInsufficientPermissions() throws {
        let cm = makeContentManager()
        let cashier = makeCashier()
        let spu = try service.createSPU(name: "Rose", description: nil, category: nil, actor: cm)
        try service.createSKU(spuID: spu.id, barcode: "NEG-SUB-1", stemCount: 3,
                              wrapType: nil, color: nil, priceCents: 500, isTaxable: false, actor: cm)
        XCTAssertThrowsError(
            try service.submitForApproval(spuID: spu.id, actor: cashier)
        ) { err in
            if case ProductError.insufficientPermissions = err { } else {
                XCTFail("expected insufficientPermissions, got \(err)")
            }
        }
    }

    func test_auditLog_usesActorID_notSyntheticUUID() throws {
        let cm = makeContentManager()
        let spu = try service.createSPU(name: "Audit Test", description: nil, category: nil, actor: cm)
        let fetch = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        fetch.predicate = NSPredicate(format: "entityID == %@", spu.id as CVarArg)
        let logs = try context.fetch(fetch)
        XCTAssertGreaterThanOrEqual(logs.count, 1)
        XCTAssertTrue(logs.allSatisfy { $0.actorID == cm.id },
                      "Audit logs must reference the real actor ID, not a synthetic UUID")
    }
}
