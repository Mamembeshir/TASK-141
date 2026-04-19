import Foundation
import CoreData

extension ETicket {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ETicket> {
        return NSFetchRequest<ETicket>(entityName: "ETicket")
    }

    @NSManaged public var id: UUID
    @NSManaged public var ticketNumber: String
    @NSManaged public var holderName: String?
    @NSManaged public var qrPayload: String
    @NSManaged public var antiCounterfeitSignature: String
    @NSManaged public var status: String
    @NSManaged public var validFrom: Date
    @NSManaged public var validTo: Date
    @NSManaged public var purchasedAt: Date
    @NSManaged public var version: Int64
    @NSManaged public var event: TicketEvent?
    @NSManaged public var checkInLogs: NSSet?

    public var checkInLogsArray: [CheckInLog] {
        (checkInLogs as? Set<CheckInLog> ?? []).sorted { $0.scannedAt < $1.scannedAt }
    }
}

extension ETicket {
    @objc(addCheckInLogsObject:)
    @NSManaged public func addToCheckInLogs(_ value: CheckInLog)
    @objc(removeCheckInLogsObject:)
    @NSManaged public func removeFromCheckInLogs(_ value: CheckInLog)
    @objc(addCheckInLogs:)
    @NSManaged public func addToCheckInLogs(_ values: NSSet)
    @objc(removeCheckInLogs:)
    @NSManaged public func removeFromCheckInLogs(_ values: NSSet)
}
