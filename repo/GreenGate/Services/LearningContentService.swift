import CoreData
import Foundation

enum LearningContentError: LocalizedError {
    case contentNotFound
    case invalidStatus(current: String, required: String)
    case emptyTitle
    case emptyBody

    var errorDescription: String? {
        switch self {
        case .contentNotFound:
            return "Learning content item not found."
        case .invalidStatus(let current, let required):
            return "Cannot perform this action: status is '\(current)', expected '\(required)'."
        case .emptyTitle:
            return "Title must not be empty."
        case .emptyBody:
            return "Body must not be empty."
        }
    }
}

/// CRUD + lifecycle for LearningContent articles.
///
/// Role policy:
///   - **Create / update**: Content Manager or Admin
///   - **Publish**:         Admin or Reviewer
///   - **Archive**:         Admin
final class LearningContentService {

    static let shared = LearningContentService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Create

    @discardableResult
    func create(
        title: String,
        body: String,
        category: String?,
        actor: User
    ) throws -> LearningContent {
        try requireRole(actor, any: [.contentManager, .admin])
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LearningContentError.emptyTitle
        }
        guard !body.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LearningContentError.emptyBody
        }
        let item = LearningContent(context: context)
        item.id        = UUID()
        item.title     = title.trimmingCharacters(in: .whitespaces)
        item.body      = body
        item.category  = category?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        item.status    = LearningContentStatus.draft.rawValue
        item.version   = 0
        item.createdAt = Date()
        item.createdBy = actor
        AuditService.shared.logCreate(
            actorID: actor.id,
            entityType: "LearningContent", entityID: item.id, context: context
        )
        try context.save()
        return item
    }

    // MARK: - Update

    func update(
        contentID: UUID,
        title: String,
        body: String,
        category: String?,
        actor: User
    ) throws {
        try requireRole(actor, any: [.contentManager, .admin])
        guard let item = try fetch(id: contentID) else {
            throw LearningContentError.contentNotFound
        }
        guard item.status != LearningContentStatus.archived.rawValue else {
            throw LearningContentError.invalidStatus(current: item.status, required: "DRAFT or PUBLISHED")
        }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LearningContentError.emptyTitle
        }
        guard !body.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LearningContentError.emptyBody
        }
        let before = "{\"title\":\"\(escape(item.title))\",\"status\":\"\(item.status)\"}"
        item.title     = title.trimmingCharacters(in: .whitespaces)
        item.body      = body
        item.category  = category?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        item.updatedAt = Date()
        item.version  += 1
        AuditService.shared.log(
            actorID: actor.id,
            action: AuditAction.update,
            entityType: "LearningContent", entityID: item.id,
            beforeJSON: before,
            afterJSON: "{\"title\":\"\(escape(item.title))\",\"status\":\"\(item.status)\"}",
            context: context
        )
        try context.save()
    }

    // MARK: - Publish (DRAFT → PUBLISHED)

    func publish(contentID: UUID, actor: User) throws {
        try requireRole(actor, any: [.admin, .reviewer])
        guard let item = try fetch(id: contentID) else {
            throw LearningContentError.contentNotFound
        }
        guard item.status == LearningContentStatus.draft.rawValue else {
            throw LearningContentError.invalidStatus(current: item.status, required: "DRAFT")
        }
        item.status    = LearningContentStatus.published.rawValue
        item.updatedAt = Date()
        item.version  += 1
        AuditService.shared.log(
            actorID: actor.id,
            action: AuditAction.update,
            entityType: "LearningContent", entityID: item.id,
            beforeJSON: "{\"status\":\"DRAFT\"}",
            afterJSON: "{\"status\":\"PUBLISHED\"}",
            context: context
        )
        try context.save()
    }

    // MARK: - Archive (PUBLISHED → ARCHIVED)

    func archive(contentID: UUID, actor: User) throws {
        try requireRole(actor, any: [.admin])
        guard let item = try fetch(id: contentID) else {
            throw LearningContentError.contentNotFound
        }
        guard item.status == LearningContentStatus.published.rawValue else {
            throw LearningContentError.invalidStatus(current: item.status, required: "PUBLISHED")
        }
        item.status    = LearningContentStatus.archived.rawValue
        item.updatedAt = Date()
        item.version  += 1
        AuditService.shared.log(
            actorID: actor.id,
            action: AuditAction.update,
            entityType: "LearningContent", entityID: item.id,
            beforeJSON: "{\"status\":\"PUBLISHED\"}",
            afterJSON: "{\"status\":\"ARCHIVED\"}",
            context: context
        )
        try context.save()
    }

    // MARK: - Fetch

    func fetchAll() throws -> [LearningContent] {
        let req = NSFetchRequest<LearningContent>(entityName: "LearningContent")
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(req)
    }

    func fetch(id: UUID) throws -> LearningContent? {
        let req = NSFetchRequest<LearningContent>(entityName: "LearningContent")
        req.predicate  = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try context.fetch(req).first
    }

    // MARK: - Helpers

    private func requireRole(_ actor: User, any roles: [Role]) throws {
        guard roles.map(\.rawValue).contains(actor.role) else {
            throw AuthError.insufficientPermissions
        }
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
