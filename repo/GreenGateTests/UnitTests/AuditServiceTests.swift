import XCTest
import CoreData
@testable import GreenGate

/// Direct coverage for AuditService convenience wrappers. Every call must
/// land as a persisted AuditLog row with the right action/entityType.
final class AuditServiceTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "store")
        container.loadPersistentStores { _, err in XCTAssertNil(err); exp.fulfill() }
        waitForExpectations(timeout: 5)
        context = container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil; container = nil
    }

    private func fetchLogs(action: String, entityID: UUID) throws -> [AuditLog] {
        let r = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        r.predicate = NSPredicate(format: "action == %@ AND entityID == %@",
                                  action, entityID as CVarArg)
        return try context.fetch(r)
    }

    func test_logCreate_writesOneRowWithCorrectAction() throws {
        let eid = UUID()
        AuditService.shared.logCreate(actorID: UUID(), entityType: "Foo",
                                       entityID: eid, context: context)
        try context.save()
        XCTAssertEqual(try fetchLogs(action: AuditAction.create, entityID: eid).count, 1)
    }

    func test_logUpdate_preservesBeforeAndAfterJSON() throws {
        let eid = UUID()
        AuditService.shared.logUpdate(
            actorID: UUID(), entityType: "Foo", entityID: eid,
            beforeJSON: "{\"a\":1}", afterJSON: "{\"a\":2}", context: context
        )
        try context.save()
        let log = try fetchLogs(action: AuditAction.update, entityID: eid).first
        XCTAssertEqual(log?.beforeJSON, "{\"a\":1}")
        XCTAssertEqual(log?.afterJSON,  "{\"a\":2}")
    }

    func test_logApprove_logReject_logVoid_logReturn_writeCorrectActions() throws {
        let eid = UUID()
        let ctx = context!
        AuditService.shared.logApprove(actorID: UUID(), entityType: "Foo", entityID: eid, context: ctx)
        AuditService.shared.logReject(actorID: UUID(), entityType: "Foo", entityID: eid, context: ctx)
        AuditService.shared.logVoid(actorID: UUID(), entityType: "Foo", entityID: eid, context: ctx)
        AuditService.shared.logReturn(actorID: UUID(), entityType: "Foo", entityID: eid, context: ctx)
        try ctx.save()
        XCTAssertEqual(try fetchLogs(action: AuditAction.approve, entityID: eid).count, 1)
        XCTAssertEqual(try fetchLogs(action: AuditAction.reject,  entityID: eid).count, 1)
        XCTAssertEqual(try fetchLogs(action: AuditAction.void,    entityID: eid).count, 1)
        XCTAssertEqual(try fetchLogs(action: AuditAction.return_, entityID: eid).count, 1)
    }

    func test_logCheckIn_encodesResultInAfterJSON() throws {
        let tid = UUID()
        AuditService.shared.logCheckIn(actorID: UUID(), ticketID: tid,
                                        result: .duplicate, context: context)
        try context.save()
        let log = try fetchLogs(action: AuditAction.checkIn, entityID: tid).first
        XCTAssertEqual(log?.entityType, "ETicket")
        XCTAssertEqual(log?.afterJSON, "{\"result\":\"DUPLICATE\"}")
    }

    func test_logImport_logExport_logShiftClose_encodeBody() throws {
        let actor = UUID()
        AuditService.shared.logImport(actorID: actor, importedCount: 7,
                                       rejectedCount: 3, context: context)
        AuditService.shared.logExport(actorID: actor, masked: true, context: context)
        AuditService.shared.logShiftClose(actorID: actor, totalSalesCents: 12345, context: context)
        try context.save()

        let imp = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        imp.predicate = NSPredicate(format: "action == %@", AuditAction.import_)
        let impLog = try context.fetch(imp).first
        XCTAssertEqual(impLog?.afterJSON, "{\"imported\":7,\"rejected\":3}")

        let exp = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        exp.predicate = NSPredicate(format: "action == %@", AuditAction.export)
        let expLog = try context.fetch(exp).first
        XCTAssertEqual(expLog?.afterJSON, "{\"masked\":true}")

        let sc = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        sc.predicate = NSPredicate(format: "action == %@", AuditAction.shiftClose)
        let scLog = try context.fetch(sc).first
        XCTAssertEqual(scLog?.afterJSON, "{\"totalSalesCents\":12345}")
    }

    func test_auditLog_isAppendOnly_writesDoNotMergeRows() throws {
        let eid = UUID()
        let actor1 = UUID(); let actor2 = UUID()
        AuditService.shared.logCreate(actorID: actor1, entityType: "Foo",
                                       entityID: eid, context: context)
        AuditService.shared.logUpdate(actorID: actor2, entityType: "Foo",
                                       entityID: eid, context: context)
        try context.save()
        let r = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        r.predicate = NSPredicate(format: "entityID == %@", eid as CVarArg)
        XCTAssertEqual(try context.fetch(r).count, 2,
                       "Audit log is append-only; each write should produce a distinct row")
    }
}
