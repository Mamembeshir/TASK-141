import Foundation
import CoreData

extension PropertyChangeHistory {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PropertyChangeHistory> {
        return NSFetchRequest<PropertyChangeHistory>(entityName: "PropertyChangeHistory")
    }

    @NSManaged public var id: UUID
    @NSManaged public var fieldName: String
    @NSManaged public var oldValue: String?
    @NSManaged public var newValue: String?
    @NSManaged public var changedAt: Date
    @NSManaged public var listing: PropertyListing?
    @NSManaged public var changedBy: User?
}
