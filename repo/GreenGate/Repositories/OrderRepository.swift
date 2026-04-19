import CoreData
import Foundation

final class OrderRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Orders

    func fetch(id: UUID) throws -> Order? {
        let r = NSFetchRequest<Order>(entityName: "Order")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetch(orderNumber: String) throws -> Order? {
        let r = NSFetchRequest<Order>(entityName: "Order")
        r.predicate = NSPredicate(format: "orderNumber == %@", orderNumber)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetchParked() throws -> [Order] {
        let r = NSFetchRequest<Order>(entityName: "Order")
        r.predicate = NSPredicate(format: "status == %@", OrderStatus.parked.rawValue)
        r.sortDescriptors = [NSSortDescriptor(key: "parkedAt", ascending: true)]
        return try context.fetch(r)
    }

    /// Orders completed in the given day range, for shift-close summaries.
    func fetchCompleted(in range: ClosedRange<Date>) throws -> [Order] {
        let r = NSFetchRequest<Order>(entityName: "Order")
        r.predicate = NSPredicate(
            format: "(status == %@ OR status == %@) AND completedAt >= %@ AND completedAt <= %@",
            OrderStatus.completed.rawValue,
            OrderStatus.returned.rawValue,
            range.lowerBound as NSDate,
            range.upperBound as NSDate
        )
        r.sortDescriptors = [NSSortDescriptor(key: "completedAt", ascending: true)]
        return try context.fetch(r)
    }

    /// Count of orders created on the given day — drives the daily sequence.
    func countOrders(on day: Date) throws -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        let r = NSFetchRequest<Order>(entityName: "Order")
        r.predicate = NSPredicate(format: "createdAt >= %@ AND createdAt < %@",
                                  start as NSDate, end as NSDate)
        return try context.count(for: r)
    }

    // MARK: - Inserts

    func insertOrder(cashier: User?, orderNumber: String) -> Order {
        let o = Order(context: context)
        o.id = UUID()
        o.orderNumber = orderNumber
        o.status = OrderStatus.open.rawValue
        o.subtotalCents = 0
        o.discountCents = 0
        o.taxCents = 0
        o.totalCents = 0
        o.orderDiscountPercent = 0
        o.version = 0
        o.createdAt = Date()
        o.cashier = cashier
        return o
    }

    func insertLineItem(order: Order, sku: ProductSKU, quantity: Int16) -> OrderLineItem {
        let li = OrderLineItem(context: context)
        li.id = UUID()
        li.quantity = quantity
        li.unitPriceCents = sku.priceCents
        li.discountCents = 0
        li.lineTotalCents = Int64(quantity) * sku.priceCents
        li.sortOrder = Int16(order.lineItemsArray.count)
        li.order = order
        li.sku = sku
        return li
    }

    func insertPayment(order: Order, tender: PaymentTenderType,
                       amountCents: Int64, memo: String?) -> PaymentRecord {
        let p = PaymentRecord(context: context)
        p.id = UUID()
        p.tenderType = tender.rawValue
        p.amountCents = amountCents
        p.referenceMemo = memo
        p.createdAt = Date()
        p.order = order
        return p
    }
}
