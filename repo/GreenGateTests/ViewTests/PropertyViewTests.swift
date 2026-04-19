import XCTest
import CoreData
@testable import GreenGate

/// View-layer checks: list cell renders status badge, change-history view
/// shows field-level diffs.
final class PropertyViewTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var service: PropertyService!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "store")
        container.loadPersistentStores { _, err in XCTAssertNil(err); exp.fulfill() }
        waitForExpectations(timeout: 5)
        context = container.viewContext
        service = PropertyService(context: context)
    }

    override func tearDownWithError() throws {
        service = nil; context = nil; container = nil
    }

    private func makeUser(role: Role) -> User {
        let u = User(context: context)
        u.id = UUID()
        u.username = "u-\(UUID().uuidString.prefix(6))"
        u.role = role.rawValue
        u.status = UserStatus.active.rawValue
        u.version = 0; u.createdAt = Date()
        return u
    }

    private func makeInput() -> PropertyService.CreateInput {
        PropertyService.CreateInput(
            title: "Loft", addressLine1: "5 Pine St", addressLine2: nil,
            city: "Austin", state: "TX", zipCode: "78701",
            squareFootage: 1000, amenities: [],
            rentCents: 300000, depositCents: 300000, leaseMonths: 12,
            availableFrom: Date().addingTimeInterval(86400)
        )
    }

    func test_listCell_showsStatusBadge() throws {
        let l = try service.create(input: makeInput(), actor: makeUser(role: .contentManager))
        let cell = PropertyListCell(style: .default, reuseIdentifier: "c")
        cell.configure(with: l)
        XCTAssertEqual(cell.titleLabel.text, "Loft")
        XCTAssertTrue(cell.addressLabel.text?.contains("TX") ?? false)
        XCTAssertEqual(cell.badge.accessibilityLabel, "Status: Draft")
    }

    func test_changeHistory_showsFieldDiffs() throws {
        let l = try service.create(input: makeInput(), actor: makeUser(role: .contentManager))
        _ = try service.update(listingID: l.id,
                               input: PropertyService.UpdateInput(rentCents: 350000),
                               actor: makeUser(role: .contentManager))
        let vc = ChangeHistoryViewController(listing: l)
        _ = vc.view  // viewDidLoad
        // Table should have at least one section with one row.
        let table = vc.view.subviews.compactMap { $0 as? UITableView }.first
        XCTAssertNotNil(table)
        XCTAssertGreaterThanOrEqual(table?.numberOfSections ?? 0, 1)
        XCTAssertGreaterThanOrEqual(table?.numberOfRows(inSection: 0) ?? 0, 1)
    }
}
