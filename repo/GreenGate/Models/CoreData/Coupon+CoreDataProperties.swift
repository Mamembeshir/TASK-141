import Foundation
import CoreData

extension Coupon {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Coupon> {
        return NSFetchRequest<Coupon>(entityName: "Coupon")
    }

    @NSManaged public var id: UUID
    @NSManaged public var code: String
    @NSManaged public var validFrom: Date
    @NSManaged public var validTo: Date
    @NSManaged public var maxUses: Int32
    @NSManaged public var currentUses: Int32
    @NSManaged public var version: Int64
    @NSManaged public var priceRule: PriceRule?

    public var isExhausted: Bool { currentUses >= maxUses }
    public var isCurrentlyValid: Bool {
        let now = Date()
        return now >= validFrom && now <= validTo && !isExhausted
    }
}
