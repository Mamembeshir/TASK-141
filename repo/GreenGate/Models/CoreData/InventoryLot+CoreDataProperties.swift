import Foundation
import CoreData

extension InventoryLot {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<InventoryLot> {
        return NSFetchRequest<InventoryLot>(entityName: "InventoryLot")
    }

    @NSManaged public var id: UUID
    @NSManaged public var onHand: Int32
    @NSManaged public var reservedCount: Int32
    @NSManaged public var lotDate: Date
    @NSManaged public var expiryDate: Date?
    @NSManaged public var version: Int64
    @NSManaged public var sku: ProductSKU?

    public var available: Int32 { onHand - reservedCount }
}
