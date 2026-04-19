import Foundation
import CoreData

extension User {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<User> {
        return NSFetchRequest<User>(entityName: "User")
    }

    @NSManaged public var id: UUID
    @NSManaged public var username: String
    @NSManaged public var role: String
    @NSManaged public var status: String
    @NSManaged public var failedLoginCount: Int16
    @NSManaged public var lockedUntil: Date?
    @NSManaged public var biometricEnabled: Bool
    @NSManaged public var version: Int64
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date?
    @NSManaged public var orders: NSSet?
    @NSManaged public var createdSPUs: NSSet?
    @NSManaged public var propertyListings: NSSet?
    @NSManaged public var propertyChanges: NSSet?
    @NSManaged public var checkIns: NSSet?
    @NSManaged public var uploadedAttachments: NSSet?
    @NSManaged public var auditLogs: NSSet?
    @NSManaged public var learningContent: NSSet?

    public var ordersArray: [Order] {
        (orders as? Set<Order> ?? []).sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Generated accessors for orders
extension User {
    @objc(addOrdersObject:)
    @NSManaged public func addToOrders(_ value: Order)
    @objc(removeOrdersObject:)
    @NSManaged public func removeFromOrders(_ value: Order)
    @objc(addOrders:)
    @NSManaged public func addToOrders(_ values: NSSet)
    @objc(removeOrders:)
    @NSManaged public func removeFromOrders(_ values: NSSet)
}
