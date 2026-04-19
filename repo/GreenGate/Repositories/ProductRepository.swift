import CoreData
import Foundation

/// Thin data-access layer for ProductSPU and ProductSKU. Business rules live
/// in `ProductService` — this file is fetches + simple inserts.
final class ProductRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - SPU

    func fetchSPU(id: UUID) throws -> ProductSPU? {
        let r = NSFetchRequest<ProductSPU>(entityName: "ProductSPU")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetchAllSPUs() throws -> [ProductSPU] {
        let r = NSFetchRequest<ProductSPU>(entityName: "ProductSPU")
        r.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(r)
    }

    func fetchSPUs(status: ProductListingStatus) throws -> [ProductSPU] {
        let r = NSFetchRequest<ProductSPU>(entityName: "ProductSPU")
        r.predicate = NSPredicate(format: "listingStatus == %@", status.rawValue)
        r.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(r)
    }

    func insertSPU(name: String, description: String?, category: String?) -> ProductSPU {
        let spu = ProductSPU(context: context)
        spu.id = UUID()
        spu.name = name
        spu.description_ = description
        spu.category = category
        spu.isListed = false
        spu.listingStatus = ProductListingStatus.draft.rawValue
        spu.pendingDelist = false
        spu.lowStockThreshold = 10
        spu.version = 0
        spu.createdAt = Date()
        return spu
    }

    // MARK: - SKU

    func fetchSKU(id: UUID) throws -> ProductSKU? {
        let r = NSFetchRequest<ProductSKU>(entityName: "ProductSKU")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetchSKU(barcode: String) throws -> ProductSKU? {
        let r = NSFetchRequest<ProductSKU>(entityName: "ProductSKU")
        r.predicate = NSPredicate(format: "barcode == %@", barcode)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetchAllSKUs() throws -> [ProductSKU] {
        let r = NSFetchRequest<ProductSKU>(entityName: "ProductSKU")
        r.sortDescriptors = [NSSortDescriptor(key: "barcode", ascending: true)]
        return try context.fetch(r)
    }

    func barcodeExists(_ barcode: String, excludingSKU excluded: UUID? = nil) throws -> Bool {
        let r = NSFetchRequest<ProductSKU>(entityName: "ProductSKU")
        if let excluded = excluded {
            r.predicate = NSPredicate(format: "barcode == %@ AND id != %@",
                                      barcode, excluded as CVarArg)
        } else {
            r.predicate = NSPredicate(format: "barcode == %@", barcode)
        }
        r.fetchLimit = 1
        return try context.count(for: r) > 0
    }

    func insertSKU(
        spu: ProductSPU,
        barcode: String,
        stemCount: Int16,
        wrapType: String?,
        color: String?,
        priceCents: Int64,
        isTaxable: Bool
    ) -> ProductSKU {
        let sku = ProductSKU(context: context)
        sku.id = UUID()
        sku.barcode = barcode
        sku.stemCount = stemCount
        sku.wrapType = wrapType
        sku.color = color
        sku.priceCents = priceCents
        sku.isTaxable = isTaxable
        sku.isActive = true
        sku.version = 0
        sku.spu = spu
        return sku
    }
}
