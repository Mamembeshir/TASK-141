import CoreData
import Foundation

final class AttachmentRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) { self.context = context }

    func fetch(id: UUID) throws -> Attachment? {
        let r = NSFetchRequest<Attachment>(entityName: "Attachment")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetch(parentType: AttachmentParentType, parentID: UUID) throws -> [Attachment] {
        let r = NSFetchRequest<Attachment>(entityName: "Attachment")
        r.predicate = NSPredicate(format: "parentType == %@ AND parentID == %@",
                                  parentType.rawValue, parentID as CVarArg)
        r.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(r)
    }

    func fetchByChecksum(_ checksum: String, parentType: AttachmentParentType,
                         parentID: UUID) throws -> Attachment? {
        let r = NSFetchRequest<Attachment>(entityName: "Attachment")
        r.predicate = NSPredicate(
            format: "checksumSHA256 == %@ AND parentType == %@ AND parentID == %@",
            checksum, parentType.rawValue, parentID as CVarArg
        )
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetchAll() throws -> [Attachment] {
        let r = NSFetchRequest<Attachment>(entityName: "Attachment")
        return try context.fetch(r)
    }
}
