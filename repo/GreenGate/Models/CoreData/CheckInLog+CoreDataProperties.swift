import Foundation
import CoreData

extension CheckInLog {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CheckInLog> {
        return NSFetchRequest<CheckInLog>(entityName: "CheckInLog")
    }

    @NSManaged public var id: UUID
    @NSManaged public var scannedAt: Date
    @NSManaged public var result: String
    @NSManaged public var deviceInfo: String?
    @NSManaged public var ticket: ETicket?
    @NSManaged public var scannedBy: User?
}
