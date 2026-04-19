import Foundation
import CoreData

extension Attachment {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Attachment> {
        return NSFetchRequest<Attachment>(entityName: "Attachment")
    }

    @NSManaged public var id: UUID
    @NSManaged public var parentType: String
    @NSManaged public var parentID: UUID
    @NSManaged public var fileName: String
    @NSManaged public var filePath: String
    @NSManaged public var fileSizeBytes: Int64
    @NSManaged public var mimeType: String
    @NSManaged public var checksumSHA256: String
    @NSManaged public var thumbnailPath: String?
    @NSManaged public var isCompressed: Bool
    @NSManaged public var licensingInfo: String?
    @NSManaged public var copyrightInfo: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var uploadedBy: User?
}
