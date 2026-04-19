import Foundation
import CoreData

extension ProductSPU {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ProductSPU> {
        return NSFetchRequest<ProductSPU>(entityName: "ProductSPU")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var description_: String?
    @NSManaged public var category: String?
    @NSManaged public var isListed: Bool
    @NSManaged public var listingStatus: String
    @NSManaged public var rejectionNotes: String?
    @NSManaged public var reviewerID: UUID?
    @NSManaged public var reviewedAt: Date?
    @NSManaged public var pendingDelist: Bool
    @NSManaged public var lowStockThreshold: Int32
    @NSManaged public var version: Int64
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date?
    @NSManaged public var skus: NSSet?
    @NSManaged public var createdBy: User?

    public var skusArray: [ProductSKU] {
        (skus as? Set<ProductSKU> ?? []).sorted { $0.barcode < $1.barcode }
    }
}

extension ProductSPU {
    @objc(addSkusObject:)
    @NSManaged public func addToSkus(_ value: ProductSKU)
    @objc(removeSkusObject:)
    @NSManaged public func removeFromSkus(_ value: ProductSKU)
    @objc(addSkus:)
    @NSManaged public func addToSkus(_ values: NSSet)
    @objc(removeSkus:)
    @NSManaged public func removeFromSkus(_ values: NSSet)
}
