import XCTest
import CoreData
@testable import GreenGate

/// Role enforcement and lifecycle state machine for LearningContentService.
final class LearningContentServiceTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var service: LearningContentService!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "store")
        container.loadPersistentStores { _, err in XCTAssertNil(err); exp.fulfill() }
        waitForExpectations(timeout: 5)
        context = container.viewContext
        service = LearningContentService(context: context)
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
        u.version = 0
        u.createdAt = Date()
        return u
    }

    // MARK: - Create

    func test_create_byContentManager_succeeds() throws {
        let cm = makeUser(role: .contentManager)
        let item = try service.create(title: "Article", body: "Body text", category: "Plants", actor: cm)
        XCTAssertEqual(item.title, "Article")
        XCTAssertEqual(item.status, LearningContentStatus.draft.rawValue)
        XCTAssertEqual(item.createdBy?.id, cm.id)
    }

    func test_create_byAdmin_succeeds() throws {
        let admin = makeUser(role: .admin)
        let item = try service.create(title: "Guide", body: "Details here", category: nil, actor: admin)
        XCTAssertEqual(item.status, LearningContentStatus.draft.rawValue)
    }

    func test_create_byCashier_throws() throws {
        let cashier = makeUser(role: .cashier)
        XCTAssertThrowsError(try service.create(title: "T", body: "B", category: nil, actor: cashier)) { err in
            XCTAssertTrue(err is AuthError, "Expected AuthError, got \(err)")
        }
    }

    func test_create_byReviewer_throws() throws {
        let reviewer = makeUser(role: .reviewer)
        XCTAssertThrowsError(try service.create(title: "T", body: "B", category: nil, actor: reviewer))
    }

    func test_create_emptyTitle_throws() throws {
        let cm = makeUser(role: .contentManager)
        XCTAssertThrowsError(try service.create(title: "  ", body: "B", category: nil, actor: cm))
    }

    func test_create_emptyBody_throws() throws {
        let cm = makeUser(role: .contentManager)
        XCTAssertThrowsError(try service.create(title: "T", body: "", category: nil, actor: cm))
    }

    // MARK: - Update

    func test_update_byContentManager_succeeds() throws {
        let cm = makeUser(role: .contentManager)
        let item = try service.create(title: "Old", body: "Body", category: nil, actor: cm)
        try service.update(contentID: item.id, title: "New", body: "Updated body",
                           category: "Floral", actor: cm)
        XCTAssertEqual(item.title, "New")
        XCTAssertEqual(item.category, "Floral")
    }

    func test_update_byCashier_throws() throws {
        let cm = makeUser(role: .contentManager)
        let cashier = makeUser(role: .cashier)
        let item = try service.create(title: "T", body: "B", category: nil, actor: cm)
        XCTAssertThrowsError(try service.update(contentID: item.id, title: "T2", body: "B2",
                                                 category: nil, actor: cashier))
    }

    func test_update_archivedItem_throws() throws {
        let admin = makeUser(role: .admin)
        let cm = makeUser(role: .contentManager)
        let item = try service.create(title: "T", body: "B", category: nil, actor: cm)
        try service.publish(contentID: item.id, actor: admin)
        try service.archive(contentID: item.id, actor: admin)
        XCTAssertThrowsError(try service.update(contentID: item.id, title: "X", body: "Y",
                                                 category: nil, actor: cm))
    }

    // MARK: - Publish (DRAFT → PUBLISHED)

    func test_publish_byAdmin_succeeds() throws {
        let admin = makeUser(role: .admin)
        let cm = makeUser(role: .contentManager)
        let item = try service.create(title: "T", body: "B", category: nil, actor: cm)
        try service.publish(contentID: item.id, actor: admin)
        XCTAssertEqual(item.status, LearningContentStatus.published.rawValue)
    }

    func test_publish_byReviewer_succeeds() throws {
        let reviewer = makeUser(role: .reviewer)
        let cm = makeUser(role: .contentManager)
        let item = try service.create(title: "T", body: "B", category: nil, actor: cm)
        try service.publish(contentID: item.id, actor: reviewer)
        XCTAssertEqual(item.status, LearningContentStatus.published.rawValue)
    }

    func test_publish_byContentManager_throws() throws {
        let cm = makeUser(role: .contentManager)
        let item = try service.create(title: "T", body: "B", category: nil, actor: cm)
        XCTAssertThrowsError(try service.publish(contentID: item.id, actor: cm))
    }

    func test_publish_alreadyPublished_throws() throws {
        let admin = makeUser(role: .admin)
        let cm = makeUser(role: .contentManager)
        let item = try service.create(title: "T", body: "B", category: nil, actor: cm)
        try service.publish(contentID: item.id, actor: admin)
        XCTAssertThrowsError(try service.publish(contentID: item.id, actor: admin))
    }

    // MARK: - Archive (PUBLISHED → ARCHIVED)

    func test_archive_byAdmin_succeeds() throws {
        let admin = makeUser(role: .admin)
        let cm = makeUser(role: .contentManager)
        let item = try service.create(title: "T", body: "B", category: nil, actor: cm)
        try service.publish(contentID: item.id, actor: admin)
        try service.archive(contentID: item.id, actor: admin)
        XCTAssertEqual(item.status, LearningContentStatus.archived.rawValue)
    }

    func test_archive_byReviewer_throws() throws {
        let reviewer = makeUser(role: .reviewer)
        let admin = makeUser(role: .admin)
        let cm = makeUser(role: .contentManager)
        let item = try service.create(title: "T", body: "B", category: nil, actor: cm)
        try service.publish(contentID: item.id, actor: admin)
        XCTAssertThrowsError(try service.archive(contentID: item.id, actor: reviewer))
    }

    func test_archive_fromDraft_throws() throws {
        let admin = makeUser(role: .admin)
        let cm = makeUser(role: .contentManager)
        let item = try service.create(title: "T", body: "B", category: nil, actor: cm)
        XCTAssertThrowsError(try service.archive(contentID: item.id, actor: admin))
    }

    // MARK: - Full lifecycle

    func test_fullLifecycle_draftToPublishedToArchived() throws {
        let cm       = makeUser(role: .contentManager)
        let reviewer = makeUser(role: .reviewer)
        let admin    = makeUser(role: .admin)

        let item = try service.create(title: "Pruning Guide", body: "Details…", category: "Care", actor: cm)
        XCTAssertEqual(item.status, LearningContentStatus.draft.rawValue)

        try service.update(contentID: item.id, title: "Pruning Guide v2", body: "Revised.",
                           category: "Care", actor: cm)
        XCTAssertEqual(item.title, "Pruning Guide v2")

        try service.publish(contentID: item.id, actor: reviewer)
        XCTAssertEqual(item.status, LearningContentStatus.published.rawValue)

        try service.archive(contentID: item.id, actor: admin)
        XCTAssertEqual(item.status, LearningContentStatus.archived.rawValue)
    }
}
