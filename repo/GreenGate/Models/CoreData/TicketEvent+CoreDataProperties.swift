import Foundation
import CoreData

extension TicketEvent {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TicketEvent> {
        return NSFetchRequest<TicketEvent>(entityName: "TicketEvent")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var venue: String?
    @NSManaged public var eventDate: Date
    @NSManaged public var doorOpenTime: Date
    @NSManaged public var doorCloseTime: Date
    @NSManaged public var totalCapacity: Int32
    @NSManaged public var soldCount: Int32
    @NSManaged public var checkedInCount: Int32
    @NSManaged public var status: String
    @NSManaged public var version: Int64
    @NSManaged public var tickets: NSSet?

    public var ticketsArray: [ETicket] {
        (tickets as? Set<ETicket> ?? []).sorted { $0.purchasedAt < $1.purchasedAt }
    }

    public var remainingCapacity: Int32 { totalCapacity - soldCount }
}

extension TicketEvent {
    @objc(addTicketsObject:)
    @NSManaged public func addToTickets(_ value: ETicket)
    @objc(removeTicketsObject:)
    @NSManaged public func removeFromTickets(_ value: ETicket)
    @objc(addTickets:)
    @NSManaged public func addToTickets(_ values: NSSet)
    @objc(removeTickets:)
    @NSManaged public func removeFromTickets(_ values: NSSet)
}
