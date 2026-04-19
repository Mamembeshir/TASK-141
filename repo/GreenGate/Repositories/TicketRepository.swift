import CoreData
import Foundation

final class TicketRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Events

    func fetchEvent(id: UUID) throws -> TicketEvent? {
        let r = NSFetchRequest<TicketEvent>(entityName: "TicketEvent")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetchAllEvents() throws -> [TicketEvent] {
        let r = NSFetchRequest<TicketEvent>(entityName: "TicketEvent")
        r.sortDescriptors = [NSSortDescriptor(key: "eventDate", ascending: true)]
        return try context.fetch(r)
    }

    func insertEvent(name: String, venue: String?, eventDate: Date,
                     doorOpen: Date, doorClose: Date, capacity: Int32) -> TicketEvent {
        let e = TicketEvent(context: context)
        e.id = UUID()
        e.name = name
        e.venue = venue
        e.eventDate = eventDate
        e.doorOpenTime = doorOpen
        e.doorCloseTime = doorClose
        e.totalCapacity = capacity
        e.soldCount = 0
        e.checkedInCount = 0
        e.status = EventStatus.draft.rawValue
        e.version = 0
        return e
    }

    // MARK: - Tickets

    func fetchTicket(id: UUID) throws -> ETicket? {
        let r = NSFetchRequest<ETicket>(entityName: "ETicket")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetchTicket(number: String) throws -> ETicket? {
        let r = NSFetchRequest<ETicket>(entityName: "ETicket")
        r.predicate = NSPredicate(format: "ticketNumber == %@", number)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetchValidTicketsPast(_ now: Date) throws -> [ETicket] {
        let r = NSFetchRequest<ETicket>(entityName: "ETicket")
        r.predicate = NSPredicate(
            format: "status == %@ AND validTo < %@",
            TicketStatus.valid.rawValue, now as NSDate
        )
        return try context.fetch(r)
    }

    func insertTicket(event: TicketEvent, holderName: String?,
                      ticketNumber: String, qrPayload: String,
                      signature: String, validFrom: Date, validTo: Date) -> ETicket {
        let t = ETicket(context: context)
        t.id = UUID()
        t.ticketNumber = ticketNumber
        t.holderName = holderName
        t.qrPayload = qrPayload
        t.antiCounterfeitSignature = signature
        t.status = TicketStatus.valid.rawValue
        t.validFrom = validFrom
        t.validTo = validTo
        t.purchasedAt = Date()
        t.version = 0
        t.event = event
        return t
    }

    func insertCheckInLog(ticket: ETicket, scannedBy: User?,
                          result: CheckInResult, deviceInfo: String?) -> CheckInLog {
        let log = CheckInLog(context: context)
        log.id = UUID()
        log.scannedAt = Date()
        log.result = result.rawValue
        log.deviceInfo = deviceInfo
        log.ticket = ticket
        log.scannedBy = scannedBy
        return log
    }
}
