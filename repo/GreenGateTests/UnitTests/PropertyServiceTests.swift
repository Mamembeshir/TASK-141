import XCTest
import CoreData
@testable import GreenGate

/// Unit tests for PropertyService: state machine, address/zip validation,
/// per-field change-history diffing.
final class PropertyServiceTests: XCTestCase {

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

    private func sampleInput(state: String = "CA", zip: String = "94107",
                             rent: Int64 = 250000) -> PropertyService.CreateInput {
        PropertyService.CreateInput(
            title: "Sunny 2BR", addressLine1: "1 Main St", addressLine2: nil,
            city: "SF", state: state, zipCode: zip,
            squareFootage: 850, amenities: ["WiFi", "Parking"],
            rentCents: rent, depositCents: 500000, leaseMonths: 12,
            availableFrom: Date().addingTimeInterval(86400)
        )
    }

    // MARK: - Validation

    func test_create_invalidState_throws() {
        XCTAssertThrowsError(try service.create(input: sampleInput(state: "California"),
                                                 actor: makeUser(role: .contentManager)))
    }

    func test_create_invalidZip_throws() {
        XCTAssertThrowsError(try service.create(input: sampleInput(zip: "abc"), actor: makeUser(role: .contentManager)))
        XCTAssertThrowsError(try service.create(input: sampleInput(zip: "1234"), actor: makeUser(role: .contentManager)))
    }

    func test_create_zipPlus4_accepted() throws {
        let l = try service.create(input: sampleInput(zip: "94107-1234"), actor: makeUser(role: .contentManager))
        XCTAssertEqual(l.zipCode, "94107-1234")
    }

    func test_create_availableFromPast_throws() {
        var input = sampleInput()
        input = PropertyService.CreateInput(
            title: input.title, addressLine1: input.addressLine1,
            addressLine2: input.addressLine2, city: input.city, state: input.state,
            zipCode: input.zipCode, squareFootage: input.squareFootage,
            amenities: input.amenities, rentCents: input.rentCents,
            depositCents: input.depositCents, leaseMonths: input.leaseMonths,
            availableFrom: Date().addingTimeInterval(-2 * 86400)
        )
        XCTAssertThrowsError(try service.create(input: input, actor: makeUser(role: .contentManager)))
    }

    // MARK: - State machine

    func test_stateMachine_happyPath() throws {
        let reviewer = makeUser(role: .reviewer)
        let l = try service.create(input: sampleInput(), actor: makeUser(role: .contentManager))
        XCTAssertEqual(l.status, PropertyStatus.draft.rawValue)
        try service.submitForReview(listingID: l.id, actor: makeUser(role: .contentManager))
        XCTAssertEqual(l.status, PropertyStatus.inReview.rawValue)
        try service.approve(listingID: l.id, reviewer: reviewer)
        XCTAssertEqual(l.status, PropertyStatus.published.rawValue)
    }

    func test_approve_byNonReviewer_throws() throws {
        let cashier = makeUser(role: .cashier)
        let l = try service.create(input: sampleInput(), actor: makeUser(role: .contentManager))
        try service.submitForReview(listingID: l.id, actor: makeUser(role: .contentManager))
        XCTAssertThrowsError(try service.approve(listingID: l.id, reviewer: cashier))
    }

    func test_reject_returnsToDraft_andRecordsNotes() throws {
        let reviewer = makeUser(role: .reviewer)
        let l = try service.create(input: sampleInput(), actor: makeUser(role: .contentManager))
        try service.submitForReview(listingID: l.id, actor: makeUser(role: .contentManager))
        try service.reject(listingID: l.id, reviewer: reviewer, notes: "Fix photos")
        XCTAssertEqual(l.status, PropertyStatus.draft.rawValue)
        XCTAssertTrue(l.changeHistoryArray.contains { $0.fieldName == "reviewNotes" })
    }

    func test_lock_byContentManager_throws() throws {
        let cm = makeUser(role: .contentManager)
        let reviewer = makeUser(role: .reviewer)
        let l = try service.create(input: sampleInput(), actor: cm)
        try service.submitForReview(listingID: l.id, actor: cm)
        try service.approve(listingID: l.id, reviewer: reviewer)
        XCTAssertThrowsError(try service.lock(listingID: l.id, admin: cm))
    }

    func test_lock_byAdmin_succeeds_andBlocksEdits() throws {
        let admin = makeUser(role: .admin)
        let l = try service.create(input: sampleInput(), actor: admin)
        try service.submitForReview(listingID: l.id, actor: admin)
        try service.approve(listingID: l.id, reviewer: admin)
        try service.lock(listingID: l.id, admin: admin)
        XCTAssertEqual(l.status, PropertyStatus.locked.rawValue)

        XCTAssertThrowsError(
            try service.update(listingID: l.id,
                               input: PropertyService.UpdateInput(rentCents: 300000),
                               actor: admin)
        ) { err in
            if case PropertyError.lockedListing = err { } else {
                XCTFail("expected lockedListing, got \(err)")
            }
        }
    }

    func test_unlock_byAdmin_restoresEdits() throws {
        let admin = makeUser(role: .admin)
        let l = try service.create(input: sampleInput(), actor: admin)
        try service.submitForReview(listingID: l.id, actor: admin)
        try service.approve(listingID: l.id, reviewer: admin)
        try service.lock(listingID: l.id, admin: admin)
        try service.unlock(listingID: l.id, admin: admin)
        XCTAssertEqual(l.status, PropertyStatus.published.rawValue)
        let changes = try service.update(listingID: l.id,
                                         input: PropertyService.UpdateInput(rentCents: 300000),
                                         actor: admin)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(l.rentCents, 300000)
    }

    // MARK: - Change history diffing

    func test_update_recordsOnePerChangedField() throws {
        let l = try service.create(input: sampleInput(rent: 200000), actor: makeUser(role: .contentManager))
        let changes = try service.update(
            listingID: l.id,
            input: PropertyService.UpdateInput(
                title: "Updated", rentCents: 250000, leaseMonths: 6
            ),
            actor: makeUser(role: .contentManager)
        )
        XCTAssertEqual(changes.count, 3)
        let fields = Set(changes.map { $0.fieldName })
        XCTAssertEqual(fields, ["title", "rentCents", "leaseMonths"])

        let rentChange = changes.first { $0.fieldName == "rentCents" }
        XCTAssertEqual(rentChange?.oldValue, "200000")
        XCTAssertEqual(rentChange?.newValue, "250000")
    }

    func test_update_noChanges_recordsNothing() throws {
        let l = try service.create(input: sampleInput(), actor: makeUser(role: .contentManager))
        let changes = try service.update(listingID: l.id,
                                          input: PropertyService.UpdateInput(),
                                          actor: makeUser(role: .contentManager))
        XCTAssertEqual(changes.count, 0)
    }
}
