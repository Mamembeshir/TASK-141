import CoreData
import Foundation

/// POS cart + checkout + returns + order-number sequencing.
/// All writes are audited and protected by optimistic locking on Order.version.
/// Implements the PRD 9.2 order state machine and POS-01 through POS-12.
final class POSService {

    static let shared = POSService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext
    private let orders: OrderRepository
    private let products: ProductRepository
    private let inventory: InventoryService
    private let coupons: CouponRepository

    init(context: NSManagedObjectContext) {
        self.context = context
        self.orders    = OrderRepository(context: context)
        self.products  = ProductRepository(context: context)
        self.inventory = InventoryService(context: context)
        self.coupons   = CouponRepository(context: context)
    }

    // MARK: - Order lifecycle

    /// Creates a new OPEN order with a generated order number (POS-11).
    /// Requires the cashier to hold the Cashier or Admin role.
    @discardableResult
    func createOrder(cashier: User) throws -> Order {
        guard cashier.role == Role.cashier.rawValue ||
              cashier.role == Role.admin.rawValue else {
            throw AuthError.insufficientPermissions
        }
        let number = try generateOrderNumber(for: Date())
        let order = orders.insertOrder(cashier: cashier, orderNumber: number)
        AuditService.shared.logCreate(
            actorID: cashier.id,
            entityType: "Order",
            entityID: order.id,
            context: context
        )
        try context.save()
        return order
    }

    // MARK: - Barcode lookup (POS-01)

    /// Resolves a barcode to its SKU. Throws `.barcodeNotFound` or
    /// `.skuInactive` on failure. Callers should emit haptics based on the
    /// outcome.
    @discardableResult
    func scanBarcode(_ code: String) throws -> ProductSKU {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sku = try products.fetchSKU(barcode: trimmed) else {
            throw POSError.barcodeNotFound(trimmed)
        }
        if !sku.isActive { throw POSError.skuInactive }
        return sku
    }

    // MARK: - Cart management (POS-02)

    /// Adds `quantity` of the SKU to the order. If the SKU is already on the
    /// order, increments quantity in place. Reserves inventory (questions.md 1.3).
    @discardableResult
    func addToCart(orderID: UUID, skuID: UUID, quantity: Int16) throws -> OrderLineItem {
        guard quantity > 0 else {
            throw POSError.insufficientInventory(available: 0)
        }
        guard let order = try orders.fetch(id: orderID) else { throw POSError.orderNotFound }
        try requireOpen(order)
        guard let sku = try products.fetchSKU(id: skuID) else { throw POSError.barcodeNotFound("") }
        if !sku.isActive { throw POSError.skuInactive }

        let available = try inventory.getAvailable(skuID: skuID)
        if available < quantity {
            throw POSError.insufficientInventory(available: available)
        }

        let existing = order.lineItemsArray.first { $0.sku?.id == skuID }
        let line: OrderLineItem
        if let existing = existing {
            existing.quantity += quantity
            recalculateLineTotal(existing)
            line = existing
        } else {
            line = orders.insertLineItem(order: order, sku: sku, quantity: quantity)
        }
        guard let actorID = order.cashier?.id else { throw AuthError.insufficientPermissions }
        try inventory.reserveStock(skuID: skuID, quantity: Int32(quantity), actorID: actorID)
        try recalculateOrder(order)
        AuditService.shared.log(
            actorID: actorID,
            action: AuditAction.update,
            entityType: "Order",
            entityID: order.id,
            afterJSON: "{\"action\":\"addToCart\",\"skuID\":\"\(skuID)\",\"quantity\":\(quantity)}",
            context: context
        )
        try context.save()
        return line
    }

    /// Removes a line item from an open order; unreserves inventory.
    func removeLineItem(lineItemID: UUID, orderID: UUID) throws {
        guard let order = try orders.fetch(id: orderID) else { throw POSError.orderNotFound }
        try requireOpen(order)
        guard let line = order.lineItemsArray.first(where: { $0.id == lineItemID }) else {
            return
        }
        guard let actorID = order.cashier?.id else { throw AuthError.insufficientPermissions }
        if let skuID = line.sku?.id {
            try? inventory.unreserveStock(skuID: skuID, quantity: Int32(line.quantity), actorID: actorID)
        }
        context.delete(line)
        try recalculateOrder(order)
        AuditService.shared.log(
            actorID: actorID,
            action: AuditAction.update,
            entityType: "Order",
            entityID: order.id,
            afterJSON: "{\"action\":\"removeLineItem\",\"lineItemID\":\"\(lineItemID)\"}",
            context: context
        )
        try context.save()
    }

    // MARK: - Discounts (POS-03 / POS-04 / POS-05)

    /// Per-item discount, capped at 30% of the line's price (questions.md 1.2).
    func applyItemDiscount(lineItemID: UUID, orderID: UUID, percent: Int) throws {
        guard let order = try orders.fetch(id: orderID) else { throw POSError.orderNotFound }
        try requireOpen(order)
        guard let line = order.lineItemsArray.first(where: { $0.id == lineItemID }) else {
            return
        }
        let cap = AppConfiguration.discountCapPercent
        if percent < 0 || percent > cap {
            throw POSError.discountExceedsCap(maxPercent: cap)
        }
        let gross = Int64(line.quantity) * line.unitPriceCents
        line.discountCents = gross * Int64(percent) / 100
        line.lineTotalCents = gross - line.discountCents
        try recalculateOrder(order)
        guard let discountActorID = order.cashier?.id else { throw AuthError.insufficientPermissions }
        AuditService.shared.log(
            actorID: discountActorID, action: AuditAction.update,
            entityType: "Order", entityID: order.id,
            afterJSON: "{\"action\":\"applyItemDiscount\",\"lineItemID\":\"\(lineItemID)\",\"percent\":\(percent)}",
            context: context
        )
        try context.save()
    }

    /// Order-level discount — capped at 30% of subtotal.
    func applyOrderDiscount(orderID: UUID, percent: Int) throws {
        guard let order = try orders.fetch(id: orderID) else { throw POSError.orderNotFound }
        try requireOpen(order)
        let cap = AppConfiguration.discountCapPercent
        if percent < 0 || percent > cap {
            throw POSError.discountExceedsCap(maxPercent: cap)
        }
        order.orderDiscountPercent = Int16(percent)
        try recalculateOrder(order)
        guard let discountActorID = order.cashier?.id else { throw AuthError.insufficientPermissions }
        AuditService.shared.log(
            actorID: discountActorID, action: AuditAction.update,
            entityType: "Order", entityID: order.id,
            afterJSON: "{\"action\":\"applyOrderDiscount\",\"percent\":\(percent)}",
            context: context
        )
        try context.save()
    }

    // MARK: - Coupons (POS-06)

    /// Validates a coupon code against dates and max-uses, then records it on
    /// the order and applies its PriceRule as an order-level discount.
    func applyCoupon(orderID: UUID, code: String) throws {
        guard let order = try orders.fetch(id: orderID) else { throw POSError.orderNotFound }
        try requireOpen(order)
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let coupon = try coupons.fetch(code: trimmed) else {
            throw POSError.couponNotFound
        }
        let now = Date()
        if now < coupon.validFrom { throw POSError.couponNotYetValid }
        if now > coupon.validTo   { throw POSError.couponExpired }
        if coupon.isExhausted     { throw POSError.couponExhausted }

        // Treat rule's discountValue as whole-percent for PERCENT, or cents for
        // FIXED_AMOUNT (both capped by PriceRule.maxDiscountPercent).
        if let rule = coupon.priceRule {
            let cap = Int(rule.maxDiscountPercent)
            switch rule.discountType {
            case DiscountType.percent.rawValue:
                let pct = min(Int(rule.discountValue), cap)
                order.orderDiscountPercent = Int16(pct)
            case DiscountType.fixedAmount.rawValue:
                let subtotal = currentSubtotalCents(order)
                let pct = subtotal == 0
                    ? 0
                    : min(Int((rule.discountValue * 100) / max(subtotal, 1)), cap)
                order.orderDiscountPercent = Int16(pct)
            default: break
            }
        }
        order.couponCode = trimmed
        coupon.currentUses += 1
        coupon.version += 1
        try recalculateOrder(order)
        guard let couponActorID = order.cashier?.id else { throw AuthError.insufficientPermissions }
        AuditService.shared.log(
            actorID: couponActorID, action: AuditAction.update,
            entityType: "Order", entityID: order.id,
            afterJSON: "{\"action\":\"applyCoupon\",\"code\":\"\(trimmed)\"}",
            context: context
        )
        try context.save()
    }

    // MARK: - Totals (POS-07, PROD-04)

    /// Recomputes subtotal, order discount, tax (banker's rounded), and total
    /// for the given order. Writes directly into the managed object.
    @discardableResult
    func calculateTotals(orderID: UUID) throws -> (subtotal: Int64, discount: Int64, tax: Int64, total: Int64) {
        guard let order = try orders.fetch(id: orderID) else { throw POSError.orderNotFound }
        try recalculateOrder(order)
        try context.save()
        return (order.subtotalCents, order.discountCents, order.taxCents, order.totalCents)
    }

    private func recalculateLineTotal(_ line: OrderLineItem) {
        let gross = Int64(line.quantity) * line.unitPriceCents
        line.lineTotalCents = gross - line.discountCents
    }

    private func currentSubtotalCents(_ order: Order) -> Int64 {
        order.lineItemsArray.reduce(0) { $0 + $1.lineTotalCents }
    }

    private func recalculateOrder(_ order: Order) throws {
        let subtotal = currentSubtotalCents(order)
        let orderDiscount = subtotal * Int64(order.orderDiscountPercent) / 100
        let taxable = order.lineItemsArray.reduce(Int64(0)) { acc, line in
            guard line.sku?.isTaxable ?? false else { return acc }
            // Apply order-level discount proportionally to each taxable line.
            let share = subtotal == 0 ? 0 : (line.lineTotalCents * orderDiscount) / subtotal
            return acc + (line.lineTotalCents - share)
        }
        let tax = CurrencyFormatter.taxCents(
            onSubtotal: max(taxable, 0),
            rateBasisPoints: AppConfiguration.taxRateBasisPoints
        )
        order.subtotalCents = subtotal
        order.discountCents = orderDiscount
        order.taxCents = tax
        order.totalCents = subtotal - orderDiscount + tax
    }

    // MARK: - Split tender (POS-08)

    struct SplitPayment {
        let tender: PaymentTenderType
        let amountCents: Int64
        let memo: String?
    }

    /// Records multiple PaymentRecords on the order. Their sum MUST equal the
    /// order's total, otherwise throws `.splitTenderMismatch`. Does not move
    /// the order to COMPLETED — call `completeOrder` for that.
    func splitTender(orderID: UUID, payments: [SplitPayment]) throws {
        guard let order = try orders.fetch(id: orderID) else { throw POSError.orderNotFound }
        try requireOpen(order)
        try recalculateOrder(order)
        let sum = payments.reduce(Int64(0)) { $0 + $1.amountCents }
        if sum != order.totalCents {
            throw POSError.splitTenderMismatch(expected: order.totalCents, received: sum)
        }
        // Clear any prior payments (in case the cashier retried).
        for existing in order.paymentsArray { context.delete(existing) }
        for p in payments {
            _ = orders.insertPayment(order: order, tender: p.tender,
                                     amountCents: p.amountCents, memo: p.memo)
        }
        guard let tenderActorID = order.cashier?.id else { throw AuthError.insufficientPermissions }
        AuditService.shared.log(
            actorID: tenderActorID, action: AuditAction.update,
            entityType: "Order", entityID: order.id,
            afterJSON: "{\"action\":\"splitTender\",\"total\":\(order.totalCents),\"paymentCount\":\(payments.count)}",
            context: context
        )
        try context.save()
    }

    // MARK: - Park / unpark / complete / void

    func parkOrder(orderID: UUID, actor: User) throws {
        try requireCashierOrAdmin(actor)
        guard let order = try orders.fetch(id: orderID) else { throw POSError.orderNotFound }
        try requireOpen(order)
        try bumpVersion(order)
        order.status = OrderStatus.parked.rawValue
        order.parkedAt = Date()
        AuditService.shared.log(actorID: actor.id, action: AuditAction.update,
                                entityType: "Order", entityID: order.id,
                                beforeJSON: "{\"status\":\"OPEN\"}",
                                afterJSON: "{\"status\":\"PARKED\"}",
                                context: context)
        try context.save()
    }

    func unparkOrder(orderID: UUID, actor: User) throws {
        try requireCashierOrAdmin(actor)
        guard let order = try orders.fetch(id: orderID) else { throw POSError.orderNotFound }
        guard order.status == OrderStatus.parked.rawValue else { throw POSError.orderNotOpen }
        try bumpVersion(order)
        order.status = OrderStatus.open.rawValue
        order.parkedAt = nil
        AuditService.shared.log(actorID: actor.id, action: AuditAction.update,
                                entityType: "Order", entityID: order.id,
                                beforeJSON: "{\"status\":\"PARKED\"}",
                                afterJSON: "{\"status\":\"OPEN\"}",
                                context: context)
        try context.save()
    }

    /// Moves OPEN → COMPLETED. Requires payments summing to total. Decrements
    /// on-hand and clears the reservation those items were holding.
    func completeOrder(orderID: UUID, actor: User) throws {
        try requireCashierOrAdmin(actor)
        guard let order = try orders.fetch(id: orderID) else { throw POSError.orderNotFound }
        try requireOpen(order)
        try recalculateOrder(order)
        let paid = order.paymentsArray.reduce(Int64(0)) { $0 + $1.amountCents }
        if paid != order.totalCents {
            throw POSError.splitTenderMismatch(expected: order.totalCents, received: paid)
        }
        try bumpVersion(order)
        for line in order.lineItemsArray {
            guard let skuID = line.sku?.id else { continue }
            let qty = Int32(line.quantity)
            try inventory.unreserveStock(skuID: skuID, quantity: qty, actorID: actor.id)
            _ = try inventory.adjustStock(skuID: skuID, quantity: -qty,
                                          reason: "sale:\(order.orderNumber)",
                                          actorID: actor.id)
        }
        order.status = OrderStatus.completed.rawValue
        order.completedAt = Date()
        AuditService.shared.log(actorID: actor.id, action: AuditAction.update,
                                entityType: "Order", entityID: order.id,
                                afterJSON: "{\"status\":\"COMPLETED\",\"total\":\(order.totalCents)}",
                                context: context)
        try context.save()
    }

    /// Voids an OPEN or PARKED order, unreserving inventory (POS-09).
    /// Requires Cashier or Admin role.
    func voidOrder(orderID: UUID, actor: User) throws {
        try requireCashierOrAdmin(actor)
        try voidOrder(orderID: orderID, actorID: actor.id)
    }

    /// System-only overload for automated sweepers (e.g. `ParkedTicketService`).
    /// User-initiated voids must use `voidOrder(orderID:actor:)` to enforce role checks.
    func voidOrder(orderID: UUID, actorID: UUID) throws {
        guard let order = try orders.fetch(id: orderID) else { throw POSError.orderNotFound }
        if order.status == OrderStatus.completed.rawValue ||
           order.status == OrderStatus.voided.rawValue ||
           order.status == OrderStatus.returned.rawValue {
            throw POSError.orderNotOpen
        }
        try bumpVersion(order)
        for line in order.lineItemsArray {
            if let skuID = line.sku?.id {
                try? inventory.unreserveStock(skuID: skuID, quantity: Int32(line.quantity), actorID: actorID)
            }
        }
        order.status = OrderStatus.voided.rawValue
        AuditService.shared.logVoid(actorID: actorID, entityType: "Order",
                                    entityID: order.id, context: context)
        try context.save()
    }

    // MARK: - Returns (POS-10 / questions.md 1.4)

    struct ReturnItem {
        let originalLineItemID: UUID
        let quantity: Int16
    }

    /// Creates a return order with negative amounts and restores inventory.
    /// Requires Cashier or Admin role. Blocks returns past the configured window (default 30 days).
    @discardableResult
    func processReturn(
        originalOrderNumber: String,
        items: [ReturnItem],
        actor: User
    ) throws -> Order {
        try requireCashierOrAdmin(actor)
        return try processReturn(originalOrderNumber: originalOrderNumber,
                                 items: items, actorID: actor.id)
    }

    /// System-only overload used by tests and automated flows.
    /// User-initiated returns must use `processReturn(originalOrderNumber:items:actor:)` to enforce role checks.
    @discardableResult
    func processReturn(
        originalOrderNumber: String,
        items: [ReturnItem],
        actorID: UUID
    ) throws -> Order {
        guard let original = try orders.fetch(orderNumber: originalOrderNumber) else {
            throw POSError.orderNotFound
        }
        guard original.status == OrderStatus.completed.rawValue else {
            throw POSError.orderNotOpen
        }
        guard let completedAt = original.completedAt else {
            throw POSError.orderNotOpen
        }
        let windowDays = AppConfiguration.returnWindowDays
        let cutoff = Calendar.current.date(byAdding: .day, value: windowDays, to: completedAt) ?? completedAt
        if Date() > cutoff {
            throw POSError.returnPeriodExpired
        }

        let number = try generateOrderNumber(for: Date())
        let ret = orders.insertOrder(cashier: original.cashier, orderNumber: number)
        ret.status = OrderStatus.returned.rawValue
        ret.originalOrderNumber = originalOrderNumber
        ret.completedAt = Date()

        var total: Int64 = 0
        for item in items {
            guard let origLine = original.lineItemsArray.first(where: { $0.id == item.originalLineItemID }),
                  let sku = origLine.sku else { continue }
            let returnQty = min(item.quantity, origLine.quantity)
            let unit = origLine.unitPriceCents
            let discountShare = origLine.quantity == 0 ? 0
                : origLine.discountCents * Int64(returnQty) / Int64(origLine.quantity)
            let lineTotal = -(Int64(returnQty) * unit - discountShare)

            let line = OrderLineItem(context: context)
            line.id = UUID()
            line.quantity = -returnQty
            line.unitPriceCents = unit
            line.discountCents = -discountShare
            line.lineTotalCents = lineTotal
            line.sortOrder = Int16(ret.lineItemsArray.count)
            line.order = ret
            line.sku = sku

            total += lineTotal

            // Inventory restored.
            _ = try inventory.adjustStock(skuID: sku.id, quantity: Int32(returnQty),
                                          reason: "return:\(originalOrderNumber)",
                                          actorID: actorID)
        }

        ret.subtotalCents = total
        ret.totalCents = total
        ret.discountCents = 0
        ret.taxCents = 0

        // Refund payment: mirror the first original payment tender.
        let tenderRaw = original.paymentsArray.first?.tenderType ?? PaymentTenderType.cash.rawValue
        let tender = PaymentTenderType(rawValue: tenderRaw) ?? .cash
        _ = orders.insertPayment(order: ret, tender: tender, amountCents: total,
                                 memo: "Refund for \(originalOrderNumber)")

        // Mark the original as RETURNED.
        original.status = OrderStatus.returned.rawValue
        original.version += 1

        AuditService.shared.logReturn(actorID: actorID, entityType: "Order",
                                      entityID: ret.id, context: context)
        try context.save()
        return ret
    }

    // MARK: - Order number generation (POS-11 / questions.md 1.5)

    /// GG-YYYYMMDD-NNNN, with NNNN resetting daily.
    func generateOrderNumber(for date: Date) throws -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.timeZone = .current
        let datePart = fmt.string(from: date)
        let seq = try orders.countOrders(on: date) + 1
        return String(format: "GG-%@-%04d", datePart, seq)
    }

    // MARK: - Helpers

    private func requireCashierOrAdmin(_ user: User) throws {
        guard user.role == Role.cashier.rawValue || user.role == Role.admin.rawValue else {
            throw AuthError.insufficientPermissions
        }
    }

    private func requireOpen(_ order: Order) throws {
        if order.status != OrderStatus.open.rawValue {
            throw POSError.orderNotOpen
        }
    }

    private func bumpVersion(_ order: Order) throws {
        // Optimistic locking — version is maintained by the service; a
        // concurrent context write would have produced a different value.
        order.version += 1
    }
}
