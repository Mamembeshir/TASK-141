import XCTest
import CoreData
@testable import GreenGate

/// HMAC signing/verification, QR payload format, validity-window logic, and
/// the ticket state machine.
final class TicketServiceTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var service: TicketService!

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "store")
        container.loadPersistentStores { _, err in XCTAssertNil(err); exp.fulfill() }
        waitForExpectations(timeout: 5)
        context = container.viewContext
        service = TicketService(context: context)
    }

    override func tearDownWithError() throws {
        service = nil; context = nil; container = nil
    }

    // MARK: - HMAC payload + verification

    func test_buildPayload_hasFiveFields_andVerifies() {
        let id = UUID()
        let from = Date()
        let to   = from.addingTimeInterval(3600)
        let (payload, sig) = AntiCounterfeitSigner.buildPayload(
            ticketNumber: "T-ABCDEFG", eventID: id, validFrom: from, validTo: to
        )
        let parts = payload.split(separator: "|")
        XCTAssertEqual(parts.count, 5, "Expected 5 fields, got: \(payload)")
        XCTAssertEqual(parts.last.map(String.init), sig)

        let parsed = try? AntiCounterfeitSigner.verify(qrPayload: payload)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.ticketNumber, "T-ABCDEFG")
        XCTAssertEqual(parsed?.eventID, id)
    }

    func test_verify_tamperedSignature_throws() {
        let id = UUID()
        let from = Date()
        let to   = from.addingTimeInterval(3600)
        let (payload, _) = AntiCounterfeitSigner.buildPayload(
            ticketNumber: "T-1", eventID: id, validFrom: from, validTo: to
        )
        // Flip the final hex char.
        var bytes = Array(payload)
        bytes[bytes.count - 1] = bytes.last == "0" ? "1" : "0"
        let tampered = String(bytes)
        XCTAssertThrowsError(try AntiCounterfeitSigner.verify(qrPayload: tampered)) { err in
            if case TicketError.signatureInvalid = err { } else {
                XCTFail("expected signatureInvalid, got \(err)")
            }
        }
    }

    func test_verify_malformedPayload_throws() {
        XCTAssertThrowsError(try AntiCounterfeitSigner.verify(qrPayload: "junk"))
        XCTAssertThrowsError(try AntiCounterfeitSigner.verify(qrPayload: "a|b|c"))
    }

    // MARK: - Event + ticket lifecycle

    private func makeAdminUser() -> User {
        let u = User(context: context)
        u.id = UUID()
        u.username = "admin-\(UUID().uuidString.prefix(6))"
        u.role = Role.admin.rawValue
        u.status = UserStatus.active.rawValue
        u.version = 0
        u.createdAt = Date()
        return u
    }

    private func makeEvent(capacity: Int32 = 5,
                           open: Date = Date().addingTimeInterval(-3600),
                           close: Date = Date().addingTimeInterval(3600)) throws -> TicketEvent {
        let e = try service.createEvent(name: "Concert", venue: "Garden",
                                        date: open, doorOpen: open,
                                        doorClose: close, capacity: capacity,
                                        actorID: UUID())
        try service.publishEvent(eventID: e.id, actor: makeAdminUser())
        return e
    }

    func test_publishEvent_movesToOnSale() throws {
        let e = try service.createEvent(name: "X", venue: nil,
                                        date: Date(),
                                        doorOpen: Date(), doorClose: Date().addingTimeInterval(3600),
                                        capacity: 10, actorID: UUID())
        XCTAssertEqual(e.status, EventStatus.draft.rawValue)
        try service.publishEvent(eventID: e.id, actor: makeAdminUser())
        XCTAssertEqual(e.status, EventStatus.onSale.rawValue)
    }

    func test_generateTicket_incrementsSold_andSoldOutAtCapacity() throws {
        let e = try makeEvent(capacity: 2)
        _ = try service.generateTicket(eventID: e.id, holderName: "A", actorID: UUID())
        XCTAssertEqual(e.soldCount, 1)
        XCTAssertEqual(e.status, EventStatus.onSale.rawValue)
        _ = try service.generateTicket(eventID: e.id, holderName: "B", actorID: UUID())
        XCTAssertEqual(e.soldCount, 2)
        XCTAssertEqual(e.status, EventStatus.soldOut.rawValue)

        XCTAssertThrowsError(try service.generateTicket(eventID: e.id, holderName: "C", actorID: UUID()))
    }
}
