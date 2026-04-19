import Foundation
import CoreData

extension PropertyListing {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PropertyListing> {
        return NSFetchRequest<PropertyListing>(entityName: "PropertyListing")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var addressLine1: String
    @NSManaged public var addressLine2: String?
    @NSManaged public var city: String
    @NSManaged public var state: String
    @NSManaged public var zipCode: String
    @NSManaged public var squareFootage: Int32
    @NSManaged public var amenities: String?
    @NSManaged public var rentCents: Int64
    @NSManaged public var depositCents: Int64
    @NSManaged public var leaseTermMonths: Int16
    @NSManaged public var availableFrom: Date
    @NSManaged public var status: String
    @NSManaged public var version: Int64
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date?
    @NSManaged public var createdBy: User?
    @NSManaged public var changeHistory: NSSet?

    public var changeHistoryArray: [PropertyChangeHistory] {
        (changeHistory as? Set<PropertyChangeHistory> ?? []).sorted { $0.changedAt < $1.changedAt }
    }

    public var amenitiesArray: [String] {
        guard let json = amenities,
              let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return array
    }
}

extension PropertyListing {
    @objc(addChangeHistoryObject:)
    @NSManaged public func addToChangeHistory(_ value: PropertyChangeHistory)
    @objc(removeChangeHistoryObject:)
    @NSManaged public func removeFromChangeHistory(_ value: PropertyChangeHistory)
    @objc(addChangeHistory:)
    @NSManaged public func addToChangeHistory(_ values: NSSet)
    @objc(removeChangeHistory:)
    @NSManaged public func removeFromChangeHistory(_ values: NSSet)
}
