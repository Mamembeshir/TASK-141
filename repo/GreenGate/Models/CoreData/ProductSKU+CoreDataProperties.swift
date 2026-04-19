import Foundation
import CoreData

extension ProductSKU {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ProductSKU> {
        return NSFetchRequest<ProductSKU>(entityName: "ProductSKU")
    }

    @NSManaged public var id: UUID
    @NSManaged public var barcode: String
    @NSManaged public var stemCount: Int16
    @NSManaged public var wrapType: String?
    @NSManaged public var color: String?
    @NSManaged public var priceCents: Int64
    @NSManaged public var isTaxable: Bool
    @NSManaged public var isActive: Bool
    @NSManaged public var version: Int64
    @NSManaged public var spu: ProductSPU?
    @NSManaged public var inventoryLots: NSSet?
    @NSManaged public var orderLineItems: NSSet?

    public var inventoryLotsArray: [InventoryLot] {
        (inventoryLots as? Set<InventoryLot> ?? []).sorted { $0.lotDate < $1.lotDate }
    }

    public var availableCount: Int32 {
        inventoryLotsArray.reduce(0) { $0 + ($1.onHand - $1.reservedCount) }
    }
}

extension ProductSKU {
    @objc(addInventoryLotsObject:)
    @NSManaged public func addToInventoryLots(_ value: InventoryLot)
    @objc(removeInventoryLotsObject:)
    @NSManaged public func removeFromInventoryLots(_ value: InventoryLot)
    @objc(addInventoryLots:)
    @NSManaged public func addToInventoryLots(_ values: NSSet)
    @objc(removeInventoryLots:)
    @NSManaged public func removeFromInventoryLots(_ values: NSSet)
}
