import Foundation
import CoreData

extension OrderLineItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OrderLineItem> {
        return NSFetchRequest<OrderLineItem>(entityName: "OrderLineItem")
    }

    @NSManaged public var id: UUID
    @NSManaged public var quantity: Int16
    @NSManaged public var unitPriceCents: Int64
    @NSManaged public var discountCents: Int64
    @NSManaged public var lineTotalCents: Int64
    @NSManaged public var sortOrder: Int16
    @NSManaged public var order: Order?
    @NSManaged public var sku: ProductSKU?
}
