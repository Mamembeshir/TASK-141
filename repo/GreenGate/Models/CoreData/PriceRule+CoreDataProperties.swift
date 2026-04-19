import Foundation
import CoreData

extension PriceRule {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PriceRule> {
        return NSFetchRequest<PriceRule>(entityName: "PriceRule")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var discountType: String
    @NSManaged public var discountValue: Int64
    @NSManaged public var appliesTo: String
    @NSManaged public var maxDiscountPercent: Int16
    @NSManaged public var isActive: Bool
    @NSManaged public var version: Int64
    @NSManaged public var coupons: NSSet?

    public var couponsArray: [Coupon] {
        (coupons as? Set<Coupon> ?? []).sorted { $0.code < $1.code }
    }
}

extension PriceRule {
    @objc(addCouponsObject:)
    @NSManaged public func addToCoupons(_ value: Coupon)
    @objc(removeCouponsObject:)
    @NSManaged public func removeFromCoupons(_ value: Coupon)
    @objc(addCoupons:)
    @NSManaged public func addToCoupons(_ values: NSSet)
    @objc(removeCoupons:)
    @NSManaged public func removeFromCoupons(_ values: NSSet)
}
