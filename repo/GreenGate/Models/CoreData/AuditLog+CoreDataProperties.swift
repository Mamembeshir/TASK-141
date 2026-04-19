import Foundation
import CoreData

extension AuditLog {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AuditLog> {
        return NSFetchRequest<AuditLog>(entityName: "AuditLog")
    }

    @NSManaged public var id: UUID
    @NSManaged public var actorID: UUID
    @NSManaged public var action: String
    @NSManaged public var entityType: String
    @NSManaged public var entityID: UUID
    @NSManaged public var beforeJSON: String?
    @NSManaged public var afterJSON: String?
    @NSManaged public var timestamp: Date
    @NSManaged public var actor: User?
}
