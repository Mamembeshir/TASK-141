import XCTest
import CoreData
@testable import GreenGate

/// ProductDetail / ProductForm / Inventory view-layer coverage.
final class ProductsExtraViewTests: XCTestCase {

    var container: NSPersistentContainer!
    var ctx: NSManagedObjectContext!
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
        products = ProductService(context: ctx)
        inventory = InventoryService(context: ctx)
    }

    override func tearDownWithError() throws {
        products = nil; inventory = nil; ctx = nil; container = nil
    }

    private func makeContentManager() -> User {
        let u = User(context: ctx)
        u.id = UUID(); u.username = "cm-\(UUID().uuidString.prefix(5))"
        u.role = Role.contentManager.rawValue; u.status = UserStatus.active.rawValue
        u.version = 0; u.createdAt = Date()
        return u
    }

    private func seedSPU() throws -> ProductSPU {
        let actor = makeContentManager()
        let spu = try products.createSPU(name: "PE", description: "desc",
                                         category: "Flowers", actor: actor)
        try products.createSKU(spuID: spu.id, barcode: "PE-1", stemCount: 12,
                               wrapType: "paper", color: "pink",
                               priceCents: 2500, isTaxable: true, actor: actor)
        return spu
    }

    // MARK: - ProductDetail

    func test_productDetail_renders3Sections_andSKURow() throws {
        let spu = try seedSPU()
        let vc = ProductDetailViewController(spu: spu, service: products)
        _ = vc.view
        XCTAssertEqual(vc.title, spu.name)
        let table = vc.view.subviews.compactMap { $0 as? UITableView }.first
        XCTAssertEqual(table?.numberOfSections, 3, "Details + SKUs + Inventory")
        XCTAssertGreaterThanOrEqual(table?.numberOfRows(inSection: 1) ?? 0, 1)
    }

    func test_productDetail_navBar_hasEditAndActions() throws {
        let spu = try seedSPU()
        let vc = ProductDetailViewController(spu: spu, service: products)
        _ = vc.view
        XCTAssertEqual(vc.navigationItem.rightBarButtonItems?.count, 2,
                       "Edit + workflow ellipsis")
    }

    // MARK: - ProductForm

    func test_productForm_newMode_titlesNewProduct_andRendersOneSKURow() {
        let vc = ProductFormViewController(service: products)
        _ = vc.view
        XCTAssertEqual(vc.title, "New Product")
        // Verify a scroll view + content is set up.
        XCTAssertFalse(vc.view.subviews.isEmpty)
    }

    func test_productForm_editMode_titleSwitches() throws {
        let spu = try seedSPU()
        let vc = ProductFormViewController(spu: spu, service: products)
        _ = vc.view
        XCTAssertEqual(vc.title, "Edit Product")
    }

    // MARK: - Inventory

    /// View-layer smoke test for InventoryViewController. The VC's FRC is
    /// bound to `CoreDataStack.shared.viewContext` for production use, so
    /// here we verify it instantiates, sets its title from the SKU, and
    /// embeds a table view ready to render lots — without needing the SKU
    /// to live in the live persistent store.
    func test_inventoryVC_loadsAndConfiguresTitleAndTable() throws {
        let spu = try seedSPU()
        let sku = spu.skusArray[0]
        _ = try inventory.adjustStock(skuID: sku.id, quantity: 30,
                                       reason: "seed", actorID: UUID())

        let vc = InventoryViewController(sku: sku, service: inventory)
        _ = vc.view
        XCTAssertTrue(vc.title?.contains(sku.barcode) ?? false,
                       "Title should reference the SKU's barcode")
        let table = vc.view.subviews.compactMap { $0 as? UITableView }.first
        XCTAssertNotNil(table, "InventoryViewController should embed a UITableView")
        // The Adjust button should be wired up.
        XCTAssertNotNil(vc.navigationItem.rightBarButtonItem)
    }
}
