import Foundation
import CoreData

extension LearningContent {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<LearningContent> {
        return NSFetchRequest<LearningContent>(entityName: "LearningContent")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var body: String
    @NSManaged public var category: String?
    @NSManaged public var status: String
    @NSManaged public var version: Int64
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date?
    @NSManaged public var createdBy: User?
}
