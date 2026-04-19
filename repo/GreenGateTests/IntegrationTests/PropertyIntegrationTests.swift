import XCTest
import CoreData
@testable import GreenGate

/// End-to-end property lifecycle: create → submit → approve → published;
/// reject → draft; lock/unlock; field-level change history.
final class PropertyIntegrationTests: XCTestCase {

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

    private func input() -> PropertyService.CreateInput {
        PropertyService.CreateInput(
            title: "Cozy 1BR", addressLine1: "22 Elm St", addressLine2: nil,
            city: "Brooklyn", state: "NY", zipCode: "11215",
            squareFootage: 650, amenities: ["WiFi"],
            rentCents: 280000, depositCents: 280000, leaseMonths: 12,
            availableFrom: Date().addingTimeInterval(86400)
        )
    }

    func test_fullLifecycle_toLocked() throws {
        let cm = makeUser(role: .contentManager)
        let reviewer = makeUser(role: .reviewer)
        let admin = makeUser(role: .admin)

        let l = try service.create(input: input(), actor: cm)
        try service.submitForReview(listingID: l.id, actor: cm)
        try service.approve(listingID: l.id, reviewer: reviewer)
        XCTAssertEqual(l.status, PropertyStatus.published.rawValue)
        try service.lock(listingID: l.id, admin: admin)
        XCTAssertEqual(l.status, PropertyStatus.locked.rawValue)
    }

    func test_rejectBackToDraft_thenReApprove() throws {
        let cm = makeUser(role: .contentManager)
        let reviewer = makeUser(role: .reviewer)
        let l = try service.create(input: input(), actor: cm)
        try service.submitForReview(listingID: l.id, actor: cm)
        try service.reject(listingID: l.id, reviewer: reviewer, notes: "Update rent")
        XCTAssertEqual(l.status, PropertyStatus.draft.rawValue)
        try service.submitForReview(listingID: l.id, actor: cm)
        try service.approve(listingID: l.id, reviewer: reviewer)
        XCTAssertEqual(l.status, PropertyStatus.published.rawValue)
    }

    func test_changeRent_recordsHistory() throws {
        let cm = makeUser(role: .contentManager)
        let l = try service.create(input: input(), actor: cm)
        _ = try service.update(listingID: l.id,
                               input: PropertyService.UpdateInput(rentCents: 320000),
                               actor: cm)
        let rentChanges = l.changeHistoryArray.filter { $0.fieldName == "rentCents" }
        XCTAssertEqual(rentChanges.count, 1)
        XCTAssertEqual(rentChanges.first?.oldValue, "280000")
        XCTAssertEqual(rentChanges.first?.newValue, "320000")
        XCTAssertEqual(rentChanges.first?.changedBy?.id, cm.id)
    }

    func test_contentManagerCannotLock() throws {
        let cm = makeUser(role: .contentManager)
        let reviewer = makeUser(role: .reviewer)
        let l = try service.create(input: input(), actor: cm)
        try service.submitForReview(listingID: l.id, actor: cm)
        try service.approve(listingID: l.id, reviewer: reviewer)
        XCTAssertThrowsError(try service.lock(listingID: l.id, admin: cm))
    }

    func test_lockBlocksAllEdits() throws {
        let admin = makeUser(role: .admin)
        let l = try service.create(input: input(), actor: admin)
        try service.submitForReview(listingID: l.id, actor: admin)
        try service.approve(listingID: l.id, reviewer: admin)
        try service.lock(listingID: l.id, admin: admin)
        XCTAssertThrowsError(
            try service.update(listingID: l.id,
                               input: PropertyService.UpdateInput(title: "Changed"),
                               actor: admin)
        )
    }
}
