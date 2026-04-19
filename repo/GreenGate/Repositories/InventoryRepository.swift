import CoreData
import Foundation

final class InventoryRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Lots

    /// Returns the primary lot for a SKU — today's lot if one exists,
    /// otherwise the most recent lot. `nil` if no lots exist.
    func primaryLot(for sku: ProductSKU) -> InventoryLot? {
        let lots = sku.inventoryLotsArray
        if lots.isEmpty { return nil }
        let cal = Calendar.current
        if let today = lots.first(where: { cal.isDateInToday($0.lotDate) }) {
            return today
        }
        return lots.max(by: { $0.lotDate < $1.lotDate })
    }

    /// Returns a lot to write against: the primary lot if present, or a new
    /// lot created today attached to the SKU.
    func ensureLot(for sku: ProductSKU) -> InventoryLot {
        if let lot = primaryLot(for: sku) { return lot }
        let lot = InventoryLot(context: context)
        lot.id = UUID()
        lot.lotDate = Date()
        lot.onHand = 0
        lot.reservedCount = 0
        lot.version = 0
        lot.sku = sku
        return lot
    }

    /// All SKUs where `onHand - reservedCount` is ≤ the given threshold.
    func fetchLowStockSKUs(threshold: Int32) throws -> [ProductSKU] {
        let all = try allSKUs()
        return all.filter { $0.availableCount <= threshold }
    }

    private func allSKUs() throws -> [ProductSKU] {
        let r = NSFetchRequest<ProductSKU>(entityName: "ProductSKU")
        return try context.fetch(r)
    }
}
