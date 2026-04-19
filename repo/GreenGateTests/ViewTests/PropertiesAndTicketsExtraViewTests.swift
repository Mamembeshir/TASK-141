import XCTest
import CoreData
@testable import GreenGate

/// Detail / form view-layer coverage for Properties and Tickets — fills the
/// remaining VCs that didn't have direct tests.
final class PropertiesAndTicketsExtraViewTests: XCTestCase {

    var container: NSPersistentContainer!
    var ctx: NSManagedObjectContext!
    var properties: PropertyService!
    var tickets: TicketService!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "store")
        container.loadPersistentStores { _, err in XCTAssertNil(err); exp.fulfill() }
        waitForExpectations(timeout: 5)
        ctx = container.viewContext
        properties = PropertyService(context: ctx)
        tickets = TicketService(context: ctx)
    }

    override func tearDownWithError() throws {
        properties = nil; tickets = nil; ctx = nil; container = nil
    }

    private func makeAdminUser() -> User {
        let u = User(context: ctx)
        u.id = UUID()
        u.username = "admin-\(UUID().uuidString.prefix(6))"
        u.role = Role.admin.rawValue
        u.status = UserStatus.active.rawValue
        u.version = 0
        u.createdAt = Date()
        return u
    }

    // MARK: - PropertyDetail

    func test_propertyDetail_rendersThreeSections() throws {
        let l = try properties.create(input: .init(
            title: "L", addressLine1: "1 St", addressLine2: nil,
            city: "Boston", state: "MA", zipCode: "02110",
            squareFootage: 600, amenities: ["WiFi"],
            rentCents: 200000, depositCents: 200000, leaseMonths: 12,
            availableFrom: Date().addingTimeInterval(86400)
        ), actor: makeAdminUser())
        let vc = PropertyDetailViewController(listing: l, service: properties)
        _ = vc.view
        XCTAssertEqual(vc.title, "L")
        let table = vc.view.subviews.compactMap { $0 as? UITableView }.first
        XCTAssertEqual(table?.numberOfSections, 3, "Details + Financials + Status")
    }

    // MARK: - PropertyForm

    func test_propertyForm_newMode_titleSwitchesAndRendersFields() {
        let vc = PropertyFormViewController(listing: nil, service: properties)
        _ = vc.view
        XCTAssertEqual(vc.title, "New Listing")
        // The form contains a scroll view with the field stack inside.
        let scrolls = vc.view.subviews.compactMap { $0 as? UIScrollView }
        XCTAssertFalse(scrolls.isEmpty, "Form should be inside a scroll view")
    }

    func test_propertyForm_editMode_titleIsEdit() throws {
        let l = try properties.create(input: .init(
            title: "X", addressLine1: "1 St", addressLine2: nil,
            city: "SF", state: "CA", zipCode: "94107",
            squareFootage: 600, amenities: [],
            rentCents: 200000, depositCents: 200000, leaseMonths: 12,
            availableFrom: Date().addingTimeInterval(86400)
        ), actor: makeAdminUser())
        let vc = PropertyFormViewController(listing: l, service: properties)
        _ = vc.view
        XCTAssertEqual(vc.title, "Edit Listing")
    }

    // MARK: - EventDetail

    func test_eventDetail_publishedEvent_showsThreeSections_andTickets() throws {
        let event = try tickets.createEvent(
            name: "E", venue: "V", date: Date(),
            doorOpen: Date().addingTimeInterval(-300),
            doorClose: Date().addingTimeInterval(3600),
            capacity: 5, actorID: UUID()
        )
        try tickets.publishEvent(eventID: event.id, actor: makeAdminUser())
        _ = try tickets.generateTicket(eventID: event.id, holderName: "A", actorID: UUID())

        let vc = EventDetailViewController(event: event, service: tickets)
        _ = vc.view
        XCTAssertEqual(vc.title, "E")
        let table = vc.view.subviews.compactMap { $0 as? UITableView }.first
        XCTAssertEqual(table?.numberOfSections, 3, "Details + Capacity + Tickets")
        // ON_SALE event → bar items include scan + Issue.
        XCTAssertGreaterThanOrEqual(vc.navigationItem.rightBarButtonItems?.count ?? 0, 2)
    }

    func test_eventDetail_newEvent_hasSaveButton() {
        let vc = EventDetailViewController(event: nil, service: tickets)
        _ = vc.view
        XCTAssertEqual(vc.title, "New Event")
        XCTAssertEqual(vc.navigationItem.rightBarButtonItem?.title, "Save",
                       "Creation mode must show a Save button")
    }
}
