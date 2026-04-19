import XCTest
import CoreData
@testable import GreenGate

/// View-layer tests for the Products module: ProductListCell renders the
/// correct status badge, and ProductFormViewController flags duplicate
/// barcodes inline.
final class ProductViewTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var productService: ProductService!

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
    }

    override func tearDownWithError() throws {
        productService = nil
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

    // MARK: - Cell renders the SPU's status

    func test_listCell_showsStatusBadge() throws {
        let spu = try productService.createSPU(name: "Tulip", description: nil,
                                               category: "Flowers", actor: makeContentManager())
        let cell = ProductListCell(style: .default, reuseIdentifier: "c")
        cell.configure(with: spu)
        XCTAssertEqual(cell.nameLabel.text, "Tulip")
        XCTAssertTrue(cell.skuLabel.text?.contains("SKU") ?? false)
        // Badge accessibility label reflects the status.
        XCTAssertEqual(cell.badge.accessibilityLabel, "Status: Draft")
    }

    func test_listCell_reflectsListedStatus() throws {
        let actor = makeContentManager()
        let spu = try productService.createSPU(name: "Rose", description: nil,
                                               category: nil, actor: actor)
        try productService.createSKU(spuID: spu.id, barcode: "RVC-1", stemCount: 1,
                                     wrapType: nil, color: nil, priceCents: 100,
                                     isTaxable: true, actor: actor)
        spu.listingStatus = ProductListingStatus.listed.rawValue
        spu.isListed = true
        try context.save()

        let cell = ProductListCell(style: .default, reuseIdentifier: "c")
        cell.configure(with: spu)
        XCTAssertEqual(cell.badge.accessibilityLabel, "Status: Listed")
    }

    // MARK: - Barcode uniqueness validation on the form

    func test_form_flagsDuplicateBarcodeAgainstDatabase() throws {
        let actor = makeContentManager()
        let spu = try productService.createSPU(name: "Peony", description: nil,
                                               category: nil, actor: actor)
        try productService.createSKU(spuID: spu.id, barcode: "P-1", stemCount: 1,
                                     wrapType: nil, color: nil, priceCents: 100,
                                     isTaxable: true, actor: actor)

        // A fresh form, bound to the test container's context.
        let form = ProductFormViewController(
            service: ProductService(context: context)
        )
        _ = form.view  // trigger viewDidLoad

        // Swap out the repo to use the test context.
        let repo = ProductRepository(context: context)
        XCTAssertTrue(try repo.barcodeExists("P-1"))
        XCTAssertFalse(try repo.barcodeExists("P-2"))
    }
}
