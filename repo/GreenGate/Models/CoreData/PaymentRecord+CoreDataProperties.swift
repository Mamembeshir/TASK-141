import Foundation
import CoreData

extension PaymentRecord {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PaymentRecord> {
        return NSFetchRequest<PaymentRecord>(entityName: "PaymentRecord")
    }

    @NSManaged public var id: UUID
    @NSManaged public var tenderType: String
    @NSManaged public var amountCents: Int64
    @NSManaged public var referenceMemo: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var order: Order?
}
