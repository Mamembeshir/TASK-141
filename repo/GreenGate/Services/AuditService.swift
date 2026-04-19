import CoreData

/// Append-only audit logging service. Every write operation in the app must call
/// one of these methods. AuditLog records are never updated or deleted.
final class AuditService {

    static let shared = AuditService()
    private init() {}

    // MARK: - Logging

    /// Records an audit event on the given context.
    /// Call this inside the same `perform` block as your data write, before saving.
    func log(
        actorID: UUID,
        action: String,
        entityType: String,
        entityID: UUID,
        beforeJSON: String? = nil,
        afterJSON: String? = nil,
        context: NSManagedObjectContext
    ) {
        let entry = AuditLog(context: context)
        entry.id = UUID()
        entry.actorID = actorID
        entry.action = action
        entry.entityType = entityType
        entry.entityID = entityID
        entry.beforeJSON = beforeJSON
        entry.afterJSON = afterJSON
        entry.timestamp = Date()
    }

    // MARK: - Convenience Wrappers

    func logCreate(actorID: UUID, entityType: String, entityID: UUID,
                   afterJSON: String? = nil, context: NSManagedObjectContext) {
        log(actorID: actorID, action: AuditAction.create,
            entityType: entityType, entityID: entityID,
            afterJSON: afterJSON, context: context)
    }

    func logUpdate(actorID: UUID, entityType: String, entityID: UUID,
                   beforeJSON: String? = nil, afterJSON: String? = nil,
                   context: NSManagedObjectContext) {
        log(actorID: actorID, action: AuditAction.update,
            entityType: entityType, entityID: entityID,
            beforeJSON: beforeJSON, afterJSON: afterJSON, context: context)
    }

    func logDelete(actorID: UUID, entityType: String, entityID: UUID,
                   beforeJSON: String? = nil, context: NSManagedObjectContext) {
        log(actorID: actorID, action: AuditAction.delete,
            entityType: entityType, entityID: entityID,
            beforeJSON: beforeJSON, context: context)
    }

    func logApprove(actorID: UUID, entityType: String, entityID: UUID,
                    context: NSManagedObjectContext) {
        log(actorID: actorID, action: AuditAction.approve,
            entityType: entityType, entityID: entityID, context: context)
    }

    func logReject(actorID: UUID, entityType: String, entityID: UUID,
                   context: NSManagedObjectContext) {
        log(actorID: actorID, action: AuditAction.reject,
            entityType: entityType, entityID: entityID, context: context)
    }

    func logVoid(actorID: UUID, entityType: String, entityID: UUID,
                 context: NSManagedObjectContext) {
        log(actorID: actorID, action: AuditAction.void,
            entityType: entityType, entityID: entityID, context: context)
    }

    func logReturn(actorID: UUID, entityType: String, entityID: UUID,
                   context: NSManagedObjectContext) {
        log(actorID: actorID, action: AuditAction.return_,
            entityType: entityType, entityID: entityID, context: context)
    }

    func logCheckIn(actorID: UUID, ticketID: UUID, result: CheckInResult,
                    context: NSManagedObjectContext) {
        log(actorID: actorID, action: AuditAction.checkIn,
            entityType: "ETicket", entityID: ticketID,
            afterJSON: "{\"result\":\"\(result.rawValue)\"}", context: context)
    }

    func logImport(actorID: UUID, importedCount: Int, rejectedCount: Int,
                   context: NSManagedObjectContext) {
        let json = "{\"imported\":\(importedCount),\"rejected\":\(rejectedCount)}"
        log(actorID: actorID, action: AuditAction.import_,
            entityType: "Import", entityID: UUID(),
            afterJSON: json, context: context)
    }

    func logExport(actorID: UUID, masked: Bool, context: NSManagedObjectContext) {
        let json = "{\"masked\":\(masked)}"
        log(actorID: actorID, action: AuditAction.export,
            entityType: "Export", entityID: UUID(),
            afterJSON: json, context: context)
    }

    func logShiftClose(actorID: UUID, totalSalesCents: Int64,
                       context: NSManagedObjectContext) {
        let json = "{\"totalSalesCents\":\(totalSalesCents)}"
        log(actorID: actorID, action: AuditAction.shiftClose,
            entityType: "Shift", entityID: UUID(),
            afterJSON: json, context: context)
    }
}

// MARK: - Audit Action Constants

enum AuditAction {
    static let create     = "CREATE"
    static let update     = "UPDATE"
    static let delete     = "DELETE"
    static let approve    = "APPROVE"
    static let reject     = "REJECT"
    static let void       = "VOID"
    static let return_    = "RETURN"
    static let checkIn    = "CHECK_IN"
    static let import_    = "IMPORT"
    static let export     = "EXPORT"
    static let shiftClose = "SHIFT_CLOSE"
    static let login      = "LOGIN"
    static let logout     = "LOGOUT"
    static let lock       = "LOCK"
    static let unlock     = "UNLOCK"
}
