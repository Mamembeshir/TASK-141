import Foundation
import CoreData

extension Order {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Order> {
        return NSFetchRequest<Order>(entityName: "Order")
    }

    @NSManaged public var id: UUID
    @NSManaged public var orderNumber: String
    @NSManaged public var status: String
    @NSManaged public var subtotalCents: Int64
    @NSManaged public var discountCents: Int64
    @NSManaged public var taxCents: Int64
    @NSManaged public var totalCents: Int64
    @NSManaged public var parkedAt: Date?
    @NSManaged public var completedAt: Date?
    @NSManaged public var originalOrderNumber: String?
    @NSManaged public var couponCode: String?
    @NSManaged public var orderDiscountPercent: Int16
    @NSManaged public var version: Int64
    @NSManaged public var createdAt: Date
    @NSManaged public var lineItems: NSSet?
    @NSManaged public var payments: NSSet?
    @NSManaged public var cashier: User?

    public var lineItemsArray: [OrderLineItem] {
        (lineItems as? Set<OrderLineItem> ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    public var paymentsArray: [PaymentRecord] {
        (payments as? Set<PaymentRecord> ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

extension Order {
    @objc(addLineItemsObject:)
    @NSManaged public func addToLineItems(_ value: OrderLineItem)
    @objc(removeLineItemsObject:)
    @NSManaged public func removeFromLineItems(_ value: OrderLineItem)
    @objc(addLineItems:)
    @NSManaged public func addToLineItems(_ values: NSSet)
    @objc(removeLineItems:)
    @NSManaged public func removeFromLineItems(_ values: NSSet)

    @objc(addPaymentsObject:)
    @NSManaged public func addToPayments(_ value: PaymentRecord)
    @objc(removePaymentsObject:)
    @NSManaged public func removeFromPayments(_ value: PaymentRecord)
    @objc(addPayments:)
    @NSManaged public func addToPayments(_ values: NSSet)
    @objc(removePayments:)
    @NSManaged public func removeFromPayments(_ values: NSSet)
}
