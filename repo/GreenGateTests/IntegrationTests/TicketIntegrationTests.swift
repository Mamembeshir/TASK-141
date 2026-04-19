import XCTest
import CoreData
@testable import GreenGate

/// End-to-end ticket flows: create → publish → generate → scan SUCCESS;
/// duplicate, expired, tampered scans; and Gate Attendant role gating.
final class TicketIntegrationTests: XCTestCase {

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

    private func makeEvent(open: Date, close: Date, capacity: Int32 = 10) throws -> TicketEvent {
        let e = try service.createEvent(name: "Concert", venue: "Garden",
                                        date: open, doorOpen: open,
                                        doorClose: close, capacity: capacity,
                                        actorID: UUID())
        try service.publishEvent(eventID: e.id, actor: makeUser(role: .admin))
        return e
    }

    // MARK: - Happy path

    func test_create_publish_generate_scan_success() throws {
        let attendant = makeUser(role: .gateAttendant)
        let event = try makeEvent(
            open: Date().addingTimeInterval(-300),
            close: Date().addingTimeInterval(3600)
        )
        let ticket = try service.generateTicket(eventID: event.id,
                                                 holderName: "Alice",
                                                 actorID: UUID())
        XCTAssertEqual(ticket.status, TicketStatus.valid.rawValue)

        let outcome = try service.checkIn(qrPayload: ticket.qrPayload,
                                          scannedBy: attendant)
        if case .success(let t) = outcome {
            XCTAssertEqual(t.id, ticket.id)
            XCTAssertEqual(t.status, TicketStatus.used.rawValue)
            XCTAssertEqual(event.checkedInCount, 1)
        } else {
            XCTFail("expected .success, got \(outcome)")
        }
    }

    // MARK: - Duplicate

    func test_scanSameTicketTwice_secondIsDuplicate() throws {
        let attendant = makeUser(role: .gateAttendant)
        let event = try makeEvent(
            open: Date().addingTimeInterval(-300),
            close: Date().addingTimeInterval(3600)
        )
        let ticket = try service.generateTicket(eventID: event.id,
                                                holderName: "Bob", actorID: UUID())
        _ = try service.checkIn(qrPayload: ticket.qrPayload, scannedBy: attendant)
        let outcome = try service.checkIn(qrPayload: ticket.qrPayload, scannedBy: attendant)
        if case .duplicate(_, let by, _) = outcome {
            XCTAssertEqual(by, attendant.username)
        } else {
            XCTFail("expected .duplicate, got \(outcome)")
        }
    }

    // MARK: - Outside validity window → EXPIRED

    func test_scanAfterClose_isExpired() throws {
        let event = try makeEvent(
            open: Date().addingTimeInterval(-7200),
            close: Date().addingTimeInterval(-3600)
        )
        let ticket = try service.generateTicket(eventID: event.id,
                                                holderName: "Carol", actorID: UUID())
        let scanner = makeUser(role: .gateAttendant)
        let outcome = try service.checkIn(qrPayload: ticket.qrPayload, scannedBy: scanner)
        if case .expired = outcome {
            XCTAssertEqual(ticket.status, TicketStatus.expired.rawValue)
        } else {
            XCTFail("expected .expired, got \(outcome)")
        }
    }

    // MARK: - Tampered signature → INVALID

    func test_scanTamperedQR_isInvalid() throws {
        let event = try makeEvent(
            open: Date().addingTimeInterval(-300),
            close: Date().addingTimeInterval(3600)
        )
        let ticket = try service.generateTicket(eventID: event.id,
                                                holderName: "Dan", actorID: UUID())
        var tampered = ticket.qrPayload
        // Replace last char.
        let last = tampered.removeLast()
        tampered.append(last == "0" ? "1" : "0")
        let scanner = makeUser(role: .gateAttendant)
        let outcome = try service.checkIn(qrPayload: tampered, scannedBy: scanner)
        if case .invalid = outcome { } else {
            XCTFail("expected .invalid, got \(outcome)")
        }
        XCTAssertEqual(ticket.status, TicketStatus.valid.rawValue) // unchanged
    }

    // MARK: - Sold out via capacity

    func test_event_transitionsToSoldOut() throws {
        let event = try makeEvent(
            open: Date().addingTimeInterval(-300),
            close: Date().addingTimeInterval(3600),
            capacity: 1
        )
        _ = try service.generateTicket(eventID: event.id, holderName: nil, actorID: UUID())
        XCTAssertEqual(event.status, EventStatus.soldOut.rawValue)
    }

    // MARK: - Gate Attendant role gating (TKT-07)

    func test_voidTicket_byNonAdmin_throws() throws {
        let event = try makeEvent(
            open: Date().addingTimeInterval(-300),
            close: Date().addingTimeInterval(3600)
        )
        let ticket = try service.generateTicket(eventID: event.id,
                                                holderName: nil, actorID: UUID())
        let attendant = makeUser(role: .gateAttendant)
        XCTAssertThrowsError(
            try service.voidTicket(ticketID: ticket.id, actorID: attendant.id, actor: attendant)
        )
    }

    func test_voidTicket_byAdmin_succeeds() throws {
        let event = try makeEvent(
            open: Date().addingTimeInterval(-300),
            close: Date().addingTimeInterval(3600)
        )
        let ticket = try service.generateTicket(eventID: event.id,
                                                holderName: nil, actorID: UUID())
        let admin = makeUser(role: .admin)
        try service.voidTicket(ticketID: ticket.id, actorID: admin.id, actor: admin)
        XCTAssertEqual(ticket.status, TicketStatus.voided.rawValue)
    }

    // MARK: - Expiry sweeper

    func test_expirySweeper_movesValidPastCloseToExpired() throws {
        let event = try makeEvent(
            open: Date().addingTimeInterval(-7200),
            close: Date().addingTimeInterval(-60)
        )
        let ticket = try service.generateTicket(eventID: event.id,
                                                holderName: nil, actorID: UUID())
        XCTAssertEqual(ticket.status, TicketStatus.valid.rawValue)
        let sweeper = TicketExpiryService(context: context)
        let touched = try sweeper.checkExpired()
        XCTAssertTrue(touched.contains(where: { $0.id == ticket.id }))
        XCTAssertEqual(ticket.status, TicketStatus.expired.rawValue)
    }
}
