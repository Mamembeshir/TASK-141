import CoreData
import CoreImage
import Foundation
import UIKit

/// Event + e-ticket lifecycle: create/publish events, generate signed tickets,
/// check-in with HMAC verification (TKT-01..07), state machine per PRD 9.3/9.5.
final class TicketService {

    static let shared = TicketService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext
    private let repo: TicketRepository

    init(context: NSManagedObjectContext) {
        self.context = context
        self.repo = TicketRepository(context: context)
    }

    /// Outcome of a `checkIn` call. Mirrors `CheckInResult` plus extra detail.
    enum CheckInOutcome {
        case success(ticket: ETicket)
        case duplicate(ticket: ETicket, scannedBy: String, scannedAt: Date)
        case expired(ticket: ETicket?)
        case invalid(reason: String)
    }

    // MARK: - Events

    /// DRAFT event with the given window (TKT-01). Admin only.
    @discardableResult
    func createEvent(name: String, venue: String?, date: Date,
                     doorOpen: Date, doorClose: Date, capacity: Int32,
                     actor: User) throws -> TicketEvent {
        guard actor.role == Role.admin.rawValue else {
            throw AuthError.insufficientPermissions
        }
        return try createEvent(name: name, venue: venue, date: date,
                               doorOpen: doorOpen, doorClose: doorClose,
                               capacity: capacity, actorID: actor.id)
    }

    /// Internal overload used by tests and import paths that supply a raw actorID.
    @discardableResult
    func createEvent(name: String, venue: String?, date: Date,
                     doorOpen: Date, doorClose: Date, capacity: Int32,
                     actorID: UUID) throws -> TicketEvent {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TicketError.signatureInvalid // generic input guard; PRD doesn't define an "event invalid" error
        }
        let event = repo.insertEvent(name: name, venue: venue, eventDate: date,
                                     doorOpen: doorOpen, doorClose: doorClose,
                                     capacity: capacity)
        AuditService.shared.logCreate(
            actorID: actorID, entityType: "TicketEvent",
            entityID: event.id, context: context
        )
        try context.save()
        return event
    }

    /// DRAFT → ON_SALE. Admin only. Actor is required and must be an Admin.
    func publishEvent(eventID: UUID, actor: User) throws {
        guard actor.role == Role.admin.rawValue else {
            throw AuthError.insufficientPermissions
        }
        guard let event = try repo.fetchEvent(id: eventID) else { throw TicketError.eventNotOnSale }
        guard event.status == EventStatus.draft.rawValue else {
            // Already on sale / sold out / closed — no-op for safety.
            throw TicketError.eventNotOnSale
        }
        event.status = EventStatus.onSale.rawValue
        event.version += 1
        AuditService.shared.log(actorID: actor.id, action: AuditAction.update,
                                entityType: "TicketEvent", entityID: event.id,
                                afterJSON: "{\"status\":\"ON_SALE\"}",
                                context: context)
        try context.save()
    }

    // MARK: - Ticket generation (TKT-02 / TKT-03)

    /// Generates a new VALID ticket. Requires Admin or Cashier role.
    /// Increments soldCount; transitions event to SOLD_OUT when capacity is reached.
    @discardableResult
    func generateTicket(eventID: UUID, holderName: String?, actor: User) throws -> ETicket {
        guard actor.role == Role.admin.rawValue || actor.role == Role.cashier.rawValue else {
            throw AuthError.insufficientPermissions
        }
        return try generateTicket(eventID: eventID, holderName: holderName, actorID: actor.id)
    }

    /// Internal overload used by tests that supply a raw actorID.
    /// Production callers must use `generateTicket(eventID:holderName:actor:)`.
    @discardableResult
    func generateTicket(eventID: UUID, holderName: String?, actorID: UUID) throws -> ETicket {
        guard let event = try repo.fetchEvent(id: eventID) else { throw TicketError.eventNotOnSale }
        guard event.status == EventStatus.onSale.rawValue else {
            throw TicketError.eventNotOnSale
        }
        if event.soldCount >= event.totalCapacity {
            throw TicketError.eventSoldOut
        }
        let number = makeTicketNumber()
        let (payload, sig) = AntiCounterfeitSigner.buildPayload(
            ticketNumber: number,
            eventID: event.id,
            validFrom: event.doorOpenTime,
            validTo: event.doorCloseTime
        )
        let ticket = repo.insertTicket(
            event: event, holderName: holderName,
            ticketNumber: number, qrPayload: payload, signature: sig,
            validFrom: event.doorOpenTime, validTo: event.doorCloseTime
        )
        event.soldCount += 1
        event.version += 1
        if event.soldCount >= event.totalCapacity {
            event.status = EventStatus.soldOut.rawValue
        }
        AuditService.shared.logCreate(
            actorID: actorID, entityType: "ETicket",
            entityID: ticket.id, context: context
        )
        try context.save()
        return ticket
    }

    // MARK: - Check-in (TKT-04 / TKT-05 / TKT-06)

    /// Verifies HMAC, validity window, and prior use. Logs every attempt with
    /// the appropriate `CheckInResult`. Idempotent for failed scans (no state
    /// change beyond logging).
    @discardableResult
    func checkIn(qrPayload: String, scannedBy: User, now: Date = Date()) throws -> CheckInOutcome {
        // Step 1+2 — parse + verify HMAC.
        let parsed: AntiCounterfeitSigner.QRComponents
        do {
            parsed = try AntiCounterfeitSigner.verify(qrPayload: qrPayload)
        } catch {
            // Signature failure — log against ticket if we can recover the number.
            let leadingNumber = qrPayload.components(separatedBy: "|").first ?? ""
            let ticket = try? repo.fetchTicket(number: leadingNumber)
            if let ticket = ticket {
                _ = repo.insertCheckInLog(ticket: ticket, scannedBy: scannedBy,
                                          result: .invalid, deviceInfo: nil)
                AuditService.shared.logCheckIn(
                    actorID: scannedBy.id, ticketID: ticket.id,
                    result: .invalid, context: context
                )
                try context.save()
            }
            return .invalid(reason: "Signature mismatch")
        }

        guard let ticket = try repo.fetchTicket(number: parsed.ticketNumber) else {
            return .invalid(reason: "Ticket not found")
        }

        // Step 3 — validity window (TKT-04 / questions.md 2.3).
        if now < ticket.validFrom || now > ticket.validTo {
            _ = repo.insertCheckInLog(ticket: ticket, scannedBy: scannedBy,
                                      result: .expired, deviceInfo: nil)
            // Move to EXPIRED if past the window.
            if now > ticket.validTo, ticket.status == TicketStatus.valid.rawValue {
                ticket.status = TicketStatus.expired.rawValue
                ticket.version += 1
            }
            AuditService.shared.logCheckIn(
                actorID: scannedBy.id, ticketID: ticket.id,
                result: .expired, context: context
            )
            try context.save()
            return .expired(ticket: ticket)
        }

        // Step 4 — already used / voided / expired.
        if ticket.status == TicketStatus.used.rawValue {
            // TKT-05: report who/when from the most recent SUCCESS log.
            let priorLog = ticket.checkInLogsArray.last { $0.result == CheckInResult.success.rawValue }
            let who = priorLog?.scannedBy?.username ?? "another attendant"
            let at  = priorLog?.scannedAt ?? Date()
            _ = repo.insertCheckInLog(ticket: ticket, scannedBy: scannedBy,
                                      result: .duplicate, deviceInfo: nil)
            AuditService.shared.logCheckIn(
                actorID: scannedBy.id, ticketID: ticket.id,
                result: .duplicate, context: context
            )
            try context.save()
            return .duplicate(ticket: ticket, scannedBy: who, scannedAt: at)
        }
        if ticket.status == TicketStatus.voided.rawValue ||
           ticket.status == TicketStatus.expired.rawValue {
            _ = repo.insertCheckInLog(ticket: ticket, scannedBy: scannedBy,
                                      result: .invalid, deviceInfo: nil)
            AuditService.shared.logCheckIn(
                actorID: scannedBy.id, ticketID: ticket.id,
                result: .invalid, context: context
            )
            try context.save()
            return .invalid(reason: "Ticket \(ticket.status.lowercased())")
        }

        // Step 5 — success.
        ticket.status = TicketStatus.used.rawValue
        ticket.version += 1
        if let event = ticket.event {
            event.checkedInCount += 1
            event.version += 1
        }
        _ = repo.insertCheckInLog(ticket: ticket, scannedBy: scannedBy,
                                  result: .success, deviceInfo: nil)
        AuditService.shared.logCheckIn(
            actorID: scannedBy.id,
            ticketID: ticket.id, result: .success, context: context
        )
        try context.save()
        return .success(ticket: ticket)
    }

    // MARK: - Admin: void ticket

    func voidTicket(ticketID: UUID, actorID: UUID, actor: User) throws {
        if actor.role != Role.admin.rawValue {
            throw AuthError.insufficientPermissions
        }
        guard let ticket = try repo.fetchTicket(id: ticketID) else {
            throw TicketError.ticketNotFound
        }
        guard ticket.status == TicketStatus.valid.rawValue else {
            throw TicketError.ticketVoided
        }
        ticket.status = TicketStatus.voided.rawValue
        ticket.version += 1
        AuditService.shared.logVoid(actorID: actorID, entityType: "ETicket",
                                    entityID: ticket.id, context: context)
        try context.save()
    }

    // MARK: - QR image

    /// Convenience helper for views that need the ticket's QR image.
    func qrImage(for ticket: ETicket, size: CGSize = CGSize(width: 240, height: 240)) -> UIImage? {
        BarcodeGenerator.qrCode(from: ticket.qrPayload, size: size)
    }

    // MARK: - Helpers

    private func makeTicketNumber() -> String {
        // 10-char base36 from a UUID — short enough for QR, unique enough at scale.
        let u = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return "T-" + String(u.prefix(10)).uppercased()
    }
}
