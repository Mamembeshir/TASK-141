import CoreData
import Foundation

/// Property-listing lifecycle + per-field change history (PRD 8.5, 9.4).
/// Writes are audited; updates are tracked one row per changed field
/// (questions.md 4.2). Optimistic locking via `version`.
final class PropertyService {

    static let shared = PropertyService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext
    private let repo: PropertyRepository

    init(context: NSManagedObjectContext) {
        self.context = context
        self.repo = PropertyRepository(context: context)
    }

    // MARK: - Input payloads

    struct CreateInput {
        let title: String
        let addressLine1: String
        let addressLine2: String?
        let city: String
        let state: String
        let zipCode: String
        let squareFootage: Int32
        let amenities: [String]
        let rentCents: Int64
        let depositCents: Int64
        let leaseMonths: Int16
        let availableFrom: Date
    }

    /// Any combination of fields to update. `nil` values are skipped.
    struct UpdateInput {
        var title: String?
        var addressLine1: String?
        var addressLine2: String??   // nested optional so you can clear a line2
        var city: String?
        var state: String?
        var zipCode: String?
        var squareFootage: Int32?
        var amenities: [String]?
        var rentCents: Int64?
        var depositCents: Int64?
        var leaseMonths: Int16?
        var availableFrom: Date?
    }

    // MARK: - Create

    /// Creates a DRAFT listing. Requires Content Manager or Admin role.
    @discardableResult
    func create(input: CreateInput, actor: User) throws -> PropertyListing {
        try requireRole(actor, any: [.contentManager, .admin])
        try Self.validate(state: input.state, zip: input.zipCode,
                          availableFrom: input.availableFrom)
        let json = Self.encodeAmenities(input.amenities)
        let listing = repo.insert(
            title: input.title, line1: input.addressLine1, line2: input.addressLine2,
            city: input.city, state: input.state.uppercased(), zip: input.zipCode,
            sqft: input.squareFootage, amenitiesJSON: json,
            rentCents: input.rentCents, depositCents: input.depositCents,
            leaseMonths: input.leaseMonths, availableFrom: input.availableFrom,
            createdBy: actor
        )
        AuditService.shared.logCreate(
            actorID: actor.id, entityType: "PropertyListing",
            entityID: listing.id, context: context
        )
        try context.save()
        return listing
    }

    // MARK: - Update (per-field change history, questions.md 4.2)

    /// Applies `input` to the listing. Each changed field produces a
    /// `PropertyChangeHistory` row. LOCKED listings reject updates
    /// (questions.md 4.1).
    @discardableResult
    func update(listingID: UUID, input: UpdateInput,
                expectedVersion: Int64? = nil, actor: User) throws -> [PropertyChangeHistory] {
        try requireRole(actor, any: [.contentManager, .admin])
        guard let listing = try repo.fetch(id: listingID) else { throw PropertyError.listingNotFound }
        if listing.status == PropertyStatus.locked.rawValue {
            throw PropertyError.lockedListing
        }
        if let expected = expectedVersion, expected != listing.version {
            throw CoreDataError.staleRecord(entityType: "PropertyListing")
        }
        try Self.validate(state: input.state ?? listing.state,
                          zip: input.zipCode ?? listing.zipCode,
                          availableFrom: input.availableFrom ?? listing.availableFrom,
                          isNew: false)

        var changes: [PropertyChangeHistory] = []
        func diff<T: Equatable>(_ field: String, _ oldValue: T, _ newValue: T?,
                                format: (T) -> String = { "\($0)" },
                                apply: (T) -> Void) {
            guard let newValue = newValue, newValue != oldValue else { return }
            changes.append(repo.insertChange(
                listing: listing, field: field,
                oldValue: format(oldValue), newValue: format(newValue), actor: actor
            ))
            apply(newValue)
        }

        diff("title",         listing.title,         input.title)         { listing.title = $0 }
        diff("addressLine1",  listing.addressLine1,  input.addressLine1)  { listing.addressLine1 = $0 }
        if let newL2 = input.addressLine2 {
            let old = listing.addressLine2 ?? ""
            let new = newL2 ?? ""
            if old != new {
                changes.append(repo.insertChange(
                    listing: listing, field: "addressLine2",
                    oldValue: old, newValue: new, actor: actor
                ))
                listing.addressLine2 = newL2
            }
        }
        diff("city",          listing.city,          input.city)          { listing.city = $0 }
        diff("state",         listing.state,         input.state?.uppercased()) { listing.state = $0 }
        diff("zipCode",       listing.zipCode,       input.zipCode)       { listing.zipCode = $0 }
        diff("squareFootage", listing.squareFootage, input.squareFootage) { listing.squareFootage = $0 }
        if let newAmen = input.amenities {
            let oldJSON = listing.amenities ?? ""
            let newJSON = Self.encodeAmenities(newAmen) ?? ""
            if oldJSON != newJSON {
                changes.append(repo.insertChange(
                    listing: listing, field: "amenities",
                    oldValue: oldJSON, newValue: newJSON, actor: actor
                ))
                listing.amenities = Self.encodeAmenities(newAmen)
            }
        }
        diff("rentCents",     listing.rentCents,     input.rentCents)     { listing.rentCents = $0 }
        diff("depositCents",  listing.depositCents,  input.depositCents)  { listing.depositCents = $0 }
        diff("leaseMonths",   listing.leaseTermMonths, input.leaseMonths) { listing.leaseTermMonths = $0 }
        if let newDate = input.availableFrom, newDate != listing.availableFrom {
            changes.append(repo.insertChange(
                listing: listing, field: "availableFrom",
                oldValue: DateFormatters.shortDate.string(from: listing.availableFrom),
                newValue: DateFormatters.shortDate.string(from: newDate),
                actor: actor
            ))
            listing.availableFrom = newDate
        }

        if !changes.isEmpty {
            listing.updatedAt = Date()
            listing.version += 1
            AuditService.shared.logUpdate(
                actorID: actor.id,
                entityType: "PropertyListing",
                entityID: listing.id,
                afterJSON: "{\"fields\":\(changes.count)}",
                context: context
            )
        }
        try context.save()
        return changes
    }

    // MARK: - State machine (PRD 9.4)

    /// DRAFT → IN_REVIEW. Content Manager (or Admin) submits.
    func submitForReview(listingID: UUID, actor: User) throws {
        try requireRole(actor, any: [.contentManager, .admin])
        try transition(listingID: listingID, expected: .draft, to: .inReview,
                       action: AuditAction.update, actor: actor)
    }

    /// IN_REVIEW → PUBLISHED. Reviewer only.
    func approve(listingID: UUID, reviewer: User) throws {
        try requireRole(reviewer, any: [.reviewer, .admin])
        try transition(listingID: listingID, expected: .inReview, to: .published,
                       action: AuditAction.approve, actor: reviewer)
    }

    /// IN_REVIEW → DRAFT with rejection notes recorded in change history.
    func reject(listingID: UUID, reviewer: User, notes: String) throws {
        try requireRole(reviewer, any: [.reviewer, .admin])
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PropertyError.changeHistoryUnavailable }
        guard let listing = try repo.fetch(id: listingID) else { throw PropertyError.listingNotFound }
        guard listing.status == PropertyStatus.inReview.rawValue else {
            throw PropertyError.invalidStatusTransition(from: listing.status, to: PropertyStatus.draft.rawValue)
        }
        _ = repo.insertChange(listing: listing, field: "reviewNotes",
                              oldValue: nil, newValue: trimmed, actor: reviewer)
        listing.status = PropertyStatus.draft.rawValue
        listing.version += 1
        AuditService.shared.logReject(actorID: reviewer.id,
                                      entityType: "PropertyListing",
                                      entityID: listing.id, context: context)
        try context.save()
    }

    /// PUBLISHED → LOCKED. Admin only. LOCKED listings reject all updates.
    func lock(listingID: UUID, admin: User) throws {
        try requireRole(admin, any: [.admin])
        try transition(listingID: listingID, expected: .published, to: .locked,
                       action: AuditAction.update, actor: admin)
    }

    /// LOCKED → PUBLISHED. Admin only.
    func unlock(listingID: UUID, admin: User) throws {
        try requireRole(admin, any: [.admin])
        try transition(listingID: listingID, expected: .locked, to: .published,
                       action: AuditAction.update, actor: admin)
    }

    /// PUBLISHED → DRAFT. Content Manager or Admin may unpublish.
    func unpublish(listingID: UUID, actor: User) throws {
        try requireRole(actor, any: [.contentManager, .admin])
        try transition(listingID: listingID, expected: .published, to: .draft,
                       action: AuditAction.update, actor: actor)
    }

    // MARK: - Attachments (floor plans)

    /// Hand-off to AttachmentService; here we just audit and bump version.
    /// `attachment` is already persisted by the caller via AttachmentService.
    func registerFloorPlan(listingID: UUID, attachmentID: UUID, actor: User) throws {
        guard let listing = try repo.fetch(id: listingID) else { throw PropertyError.listingNotFound }
        if listing.status == PropertyStatus.locked.rawValue {
            throw PropertyError.lockedListing
        }
        _ = repo.insertChange(listing: listing, field: "floorPlanAdded",
                              oldValue: nil, newValue: attachmentID.uuidString, actor: actor)
        listing.version += 1
        AuditService.shared.logUpdate(
            actorID: actor.id, entityType: "PropertyListing",
            entityID: listing.id, context: context
        )
        try context.save()
    }

    // MARK: - Validation (PROP-01, PROP-05)

    /// US state = 2 letters. ZIP = 5 digits or 5+4. availableFrom must be
    /// today or future when creating a new listing.
    static func validate(state: String, zip: String, availableFrom: Date,
                         isNew: Bool = true) throws {
        let stateTrimmed = state.trimmingCharacters(in: .whitespaces)
        if stateTrimmed.count != 2 || !stateTrimmed.uppercased().allSatisfy({ $0.isLetter }) {
            throw PropertyError.invalidUSState
        }
        let zipPattern = #"^\d{5}(-\d{4})?$"#
        if zip.range(of: zipPattern, options: .regularExpression) == nil {
            throw PropertyError.invalidZipCode
        }
        if isNew {
            let startOfToday = Calendar.current.startOfDay(for: Date())
            if availableFrom < startOfToday {
                throw PropertyError.futureDateRequired
            }
        }
    }

    // MARK: - Helpers

    private static func encodeAmenities(_ arr: [String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: arr) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func transition(listingID: UUID, expected: PropertyStatus,
                            to target: PropertyStatus, action: String, actor: User) throws {
        guard let listing = try repo.fetch(id: listingID) else { throw PropertyError.listingNotFound }
        if listing.status == PropertyStatus.locked.rawValue && target != .published {
            throw PropertyError.lockedListing
        }
        guard listing.status == expected.rawValue else {
            throw PropertyError.invalidStatusTransition(from: listing.status, to: target.rawValue)
        }
        listing.status = target.rawValue
        listing.version += 1
        AuditService.shared.log(
            actorID: actor.id, action: action,
            entityType: "PropertyListing", entityID: listing.id,
            beforeJSON: "{\"status\":\"\(expected.rawValue)\"}",
            afterJSON: "{\"status\":\"\(target.rawValue)\"}",
            context: context
        )
        try context.save()
    }

    private func requireRole(_ user: User, any roles: [Role]) throws {
        if !roles.contains(where: { $0.rawValue == user.role }) {
            throw AuthError.insufficientPermissions
        }
    }
}
