import CoreData
import Foundation

final class PropertyRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetch(id: UUID) throws -> PropertyListing? {
        let r = NSFetchRequest<PropertyListing>(entityName: "PropertyListing")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetchAll() throws -> [PropertyListing] {
        let r = NSFetchRequest<PropertyListing>(entityName: "PropertyListing")
        r.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        return try context.fetch(r)
    }

    func insert(title: String, line1: String, line2: String?, city: String,
                state: String, zip: String, sqft: Int32, amenitiesJSON: String?,
                rentCents: Int64, depositCents: Int64, leaseMonths: Int16,
                availableFrom: Date, createdBy: User?) -> PropertyListing {
        let l = PropertyListing(context: context)
        l.id = UUID()
        l.title = title
        l.addressLine1 = line1
        l.addressLine2 = line2
        l.city = city
        l.state = state
        l.zipCode = zip
        l.squareFootage = sqft
        l.amenities = amenitiesJSON
        l.rentCents = rentCents
        l.depositCents = depositCents
        l.leaseTermMonths = leaseMonths
        l.availableFrom = availableFrom
        l.status = PropertyStatus.draft.rawValue
        l.version = 0
        l.createdAt = Date()
        l.createdBy = createdBy
        return l
    }

    func insertChange(listing: PropertyListing, field: String,
                      oldValue: String?, newValue: String?, actor: User?) -> PropertyChangeHistory {
        let h = PropertyChangeHistory(context: context)
        h.id = UUID()
        h.fieldName = field
        h.oldValue = oldValue
        h.newValue = newValue
        h.changedAt = Date()
        h.listing = listing
        h.changedBy = actor
        return h
    }
}
