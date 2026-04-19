import CoreData
import Foundation

enum InventoryError: LocalizedError {
    case skuNotFound
    case negativeStock(available: Int32)
    case reservationBelowZero
    case staleRecord

    var errorDescription: String? {
        switch self {
        case .skuNotFound:                 return "SKU not found."
        case .negativeStock(let a):        return "Adjustment would leave \(a) on hand — cannot go below zero."
        case .reservationBelowZero:        return "Cannot unreserve more units than are currently reserved."
        case .staleRecord:                 return "This inventory was modified by another process. Please refresh and try again."
        }
    }
}

/// Per-SKU inventory tracked against `InventoryLot` rows (PROD-05).
/// Exposes the operations POS and the inventory screen need:
/// adjustStock, reserveStock, unreserveStock, getAvailable, checkLowStock.
final class InventoryService {

    static let defaultLowStockThreshold: Int32 = 10  // PROD-06
    static let shared = InventoryService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext
    private let repo: InventoryRepository
    private let productRepo: ProductRepository

    init(context: NSManagedObjectContext) {
        self.context = context
        self.repo = InventoryRepository(context: context)
        self.productRepo = ProductRepository(context: context)
    }

    // MARK: - Stock adjustment

    /// Adjusts on-hand count on the SKU's primary lot. `quantity` may be
    /// negative (shrinkage, write-off) or positive (receive). Enforces
    /// on-hand ≥ 0.
    @discardableResult
    func adjustStock(
        skuID: UUID,
        quantity: Int32,
        reason: String,
        actorID: UUID
    ) throws -> InventoryLot {
        guard let sku = try productRepo.fetchSKU(id: skuID) else { throw InventoryError.skuNotFound }
        let lot = repo.ensureLot(for: sku)

        let expectedVersion = lot.version
        let newOnHand = lot.onHand + quantity
        if newOnHand < 0 {
            throw InventoryError.negativeStock(available: lot.onHand - lot.reservedCount)
        }
        guard lot.version == expectedVersion else { throw InventoryError.staleRecord }

        let before = "{\"onHand\":\(lot.onHand),\"reserved\":\(lot.reservedCount)}"
        lot.onHand = newOnHand
        lot.version = expectedVersion + 1

        AuditService.shared.log(
            actorID: actorID,
            action: AuditAction.update,
            entityType: "InventoryLot",
            entityID: lot.id,
            beforeJSON: before,
            afterJSON: "{\"onHand\":\(lot.onHand),\"reserved\":\(lot.reservedCount),\"reason\":\"\(escape(reason))\",\"delta\":\(quantity)}",
            context: context
        )
        try context.save()
        return lot
    }

    // MARK: - Reservations (used by POS)

    /// Increments `reservedCount` across the SKU's lots, oldest first, up to
    /// `quantity`. Caller is expected to have already checked availability.
    func reserveStock(skuID: UUID, quantity: Int32, actorID: UUID = UUID()) throws {
        guard quantity > 0 else { return }
        guard let sku = try productRepo.fetchSKU(id: skuID) else { throw InventoryError.skuNotFound }
        let lot = repo.ensureLot(for: sku)
        let expectedVersion = lot.version
        guard lot.version == expectedVersion else { throw InventoryError.staleRecord }
        let before = "{\"reservedCount\":\(lot.reservedCount)}"
        lot.reservedCount += quantity
        lot.version = expectedVersion + 1
        AuditService.shared.log(
            actorID: actorID,
            action: AuditAction.update,
            entityType: "InventoryLot",
            entityID: lot.id,
            beforeJSON: before,
            afterJSON: "{\"reservedCount\":\(lot.reservedCount),\"delta\":\(quantity)}",
            context: context
        )
        try context.save()
    }

    /// Decrements `reservedCount`. Used on order void/expire or ticket unpark.
    func unreserveStock(skuID: UUID, quantity: Int32, actorID: UUID = UUID()) throws {
        guard quantity > 0 else { return }
        guard let sku = try productRepo.fetchSKU(id: skuID) else { throw InventoryError.skuNotFound }
        let lot = repo.ensureLot(for: sku)
        let expectedVersion = lot.version
        if lot.reservedCount < quantity { throw InventoryError.reservationBelowZero }
        guard lot.version == expectedVersion else { throw InventoryError.staleRecord }
        let before = "{\"reservedCount\":\(lot.reservedCount)}"
        lot.reservedCount -= quantity
        lot.version = expectedVersion + 1
        AuditService.shared.log(
            actorID: actorID,
            action: AuditAction.update,
            entityType: "InventoryLot",
            entityID: lot.id,
            beforeJSON: before,
            afterJSON: "{\"reservedCount\":\(lot.reservedCount),\"delta\":-\(quantity)}",
            context: context
        )
        try context.save()
    }

    // MARK: - Queries

    /// `onHand - reservedCount` summed across all lots for the SKU.
    func getAvailable(skuID: UUID) throws -> Int32 {
        guard let sku = try productRepo.fetchSKU(id: skuID) else { throw InventoryError.skuNotFound }
        return sku.availableCount
    }

    /// All SKUs at or below the given threshold (PROD-06, default 10).
    func checkLowStock(threshold: Int32 = InventoryService.defaultLowStockThreshold) throws -> [ProductSKU] {
        try repo.fetchLowStockSKUs(threshold: threshold)
    }

    // MARK: - Helpers

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
