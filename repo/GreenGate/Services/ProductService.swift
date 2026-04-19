import CoreData
import Foundation

/// Product-related errors for SPU/SKU management and the listing approval
/// state machine (PRD 9.1, PROD-01/02/07).
enum ProductError: LocalizedError {
    case spuNotFound
    case skuNotFound
    case nameRequired
    case emptyBarcode
    case duplicateBarcode(String)
    case skuRequiredForApproval
    case invalidStatusTransition(from: ProductListingStatus, to: ProductListingStatus)
    case rejectionNotesRequired
    case insufficientPermissions
    case staleRecord

    var errorDescription: String? {
        switch self {
        case .spuNotFound:                 return "Product not found."
        case .skuNotFound:                 return "SKU not found."
        case .nameRequired:                return "Product name is required."
        case .emptyBarcode:                return "Barcode cannot be empty."
        case .duplicateBarcode(let b):     return "Barcode '\(b)' is already in use."
        case .skuRequiredForApproval:      return "At least one SKU is required before submitting for approval."
        case .invalidStatusTransition(let f, let t):
            return "Cannot transition product from \(f.displayName) to \(t.displayName)."
        case .rejectionNotesRequired:      return "Rejection notes are required."
        case .insufficientPermissions:     return "You do not have permission to perform this action."
        case .staleRecord:                 return "This product was modified by another process. Please refresh and try again."
        }
    }
}

/// SPU/SKU lifecycle plus the listing-approval state machine from PRD 9.1.
/// All writes are audited and protected by optimistic locking on `version`.
final class ProductService {

    static let shared = ProductService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext
    private let repo: ProductRepository

    init(context: NSManagedObjectContext) {
        self.context = context
        self.repo = ProductRepository(context: context)
    }

    // MARK: - Create (PROD-01)

    /// Creates a DRAFT SPU. Business rule: a brand-new SPU is always DRAFT
    /// with no SKUs; SKUs are added separately via `createSKU`.
    /// Requires Content Manager or Admin role.
    @discardableResult
    func createSPU(
        name: String,
        description: String?,
        category: String?,
        actor: User
    ) throws -> ProductSPU {
        try requireContentManagerOrAdmin(actor)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProductError.nameRequired }

        let spu = repo.insertSPU(name: trimmed, description: description, category: category)
        AuditService.shared.logCreate(
            actorID: actor.id, entityType: "ProductSPU",
            entityID: spu.id, context: context
        )
        try context.save()
        return spu
    }

    // MARK: - Create SKU (PROD-01/02)

    /// Creates a SKU attached to the given SPU. Enforces barcode uniqueness.
    /// Requires Content Manager or Admin role.
    @discardableResult
    func createSKU(
        spuID: UUID,
        barcode: String,
        stemCount: Int16,
        wrapType: String?,
        color: String?,
        priceCents: Int64,
        isTaxable: Bool,
        actor: User
    ) throws -> ProductSKU {
        try requireContentManagerOrAdmin(actor)
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProductError.emptyBarcode }
        guard let spu = try repo.fetchSPU(id: spuID) else { throw ProductError.spuNotFound }
        if try repo.barcodeExists(trimmed) {
            throw ProductError.duplicateBarcode(trimmed)
        }

        let sku = repo.insertSKU(
            spu: spu,
            barcode: trimmed,
            stemCount: stemCount,
            wrapType: wrapType,
            color: color,
            priceCents: priceCents,
            isTaxable: isTaxable
        )
        AuditService.shared.logCreate(
            actorID: actor.id, entityType: "ProductSKU",
            entityID: sku.id, context: context
        )
        try context.save()
        return sku
    }

    // MARK: - Listing state machine (PRD 9.1, PROD-07)

    /// DRAFT → PENDING_APPROVAL.
    /// Requires at least one SKU (questions.md 3.2 — nothing to list otherwise).
    /// Requires Content Manager or Admin role.
    func submitForApproval(spuID: UUID, actor: User) throws {
        try requireContentManagerOrAdmin(actor)
        try transition(spuID: spuID, to: .pendingApproval, actorID: actor.id) { spu in
            if spu.skusArray.isEmpty { throw ProductError.skuRequiredForApproval }
            spu.rejectionNotes = nil
            spu.pendingDelist = false
        }
    }

    /// PENDING_APPROVAL → LISTED. Reviewer-only.
    func approve(spuID: UUID, reviewerID: UUID, reviewer: User) throws {
        try requireReviewer(reviewer)
        try transition(spuID: spuID, to: nil, actorID: reviewerID, auditAction: AuditAction.approve) { spu in
            let wasDelistRequest = spu.pendingDelist
            guard spu.listingStatus == ProductListingStatus.pendingApproval.rawValue else {
                throw ProductError.invalidStatusTransition(
                    from: ProductListingStatus(rawValue: spu.listingStatus) ?? .draft,
                    to: wasDelistRequest ? .delisted : .listed
                )
            }
            if wasDelistRequest {
                spu.listingStatus = ProductListingStatus.delisted.rawValue
                spu.isListed = false
                spu.pendingDelist = false
            } else {
                spu.listingStatus = ProductListingStatus.listed.rawValue
                spu.isListed = true
            }
            spu.reviewerID = reviewerID
            spu.reviewedAt = Date()
            spu.rejectionNotes = nil
        }
    }

    /// PENDING_APPROVAL → DRAFT with rejection notes. Reviewer-only.
    func reject(spuID: UUID, reviewerID: UUID, reviewer: User, notes: String) throws {
        try requireReviewer(reviewer)
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProductError.rejectionNotesRequired }

        try transition(spuID: spuID, to: nil, actorID: reviewerID, auditAction: AuditAction.reject) { spu in
            guard spu.listingStatus == ProductListingStatus.pendingApproval.rawValue else {
                throw ProductError.invalidStatusTransition(
                    from: ProductListingStatus(rawValue: spu.listingStatus) ?? .draft,
                    to: .draft
                )
            }
            let wasDelistRequest = spu.pendingDelist
            spu.listingStatus = wasDelistRequest
                ? ProductListingStatus.listed.rawValue
                : ProductListingStatus.draft.rawValue
            spu.isListed = wasDelistRequest
            spu.pendingDelist = false
            spu.rejectionNotes = trimmed
            spu.reviewerID = reviewerID
            spu.reviewedAt = Date()
        }
    }

    /// LISTED → PENDING_APPROVAL for delisting.
    /// Requires Content Manager or Admin role.
    func requestDelist(spuID: UUID, actor: User) throws {
        try requireContentManagerOrAdmin(actor)
        try transition(spuID: spuID, to: .pendingApproval, actorID: actor.id) { spu in
            guard spu.listingStatus == ProductListingStatus.listed.rawValue else {
                throw ProductError.invalidStatusTransition(
                    from: ProductListingStatus(rawValue: spu.listingStatus) ?? .draft,
                    to: .pendingApproval
                )
            }
            spu.pendingDelist = true
            spu.rejectionNotes = nil
        }
    }

    /// PENDING_APPROVAL (delist request) → DELISTED. Reviewer-only.
    func approveDelist(spuID: UUID, reviewerID: UUID, reviewer: User) throws {
        try requireReviewer(reviewer)
        try transition(spuID: spuID, to: nil, actorID: reviewerID, auditAction: AuditAction.approve) { spu in
            guard spu.listingStatus == ProductListingStatus.pendingApproval.rawValue,
                  spu.pendingDelist else {
                throw ProductError.invalidStatusTransition(
                    from: ProductListingStatus(rawValue: spu.listingStatus) ?? .draft,
                    to: .delisted
                )
            }
            spu.listingStatus = ProductListingStatus.delisted.rawValue
            spu.isListed = false
            spu.pendingDelist = false
            spu.reviewerID = reviewerID
            spu.reviewedAt = Date()
        }
    }

    // MARK: - State-machine plumbing

    /// Looks up an SPU, applies `mutate`, bumps `version` (optimistic lock)
    /// and writes an audit entry.
    private func transition(
        spuID: UUID,
        to target: ProductListingStatus?,
        actorID: UUID,
        auditAction: String = AuditAction.update,
        mutate: (ProductSPU) throws -> Void
    ) throws {
        guard let spu = try repo.fetchSPU(id: spuID) else { throw ProductError.spuNotFound }
        let expectedVersion = spu.version
        let beforeStatus = spu.listingStatus

        try mutate(spu)
        if let target = target {
            spu.listingStatus = target.rawValue
        }
        spu.updatedAt = Date()

        // Optimistic lock — the mutate block runs on the fetched object, which
        // could have been changed between fetch and here by a concurrent context.
        guard spu.version == expectedVersion else {
            throw ProductError.staleRecord
        }
        spu.version = expectedVersion + 1

        AuditService.shared.log(
            actorID: actorID,
            action: auditAction,
            entityType: "ProductSPU",
            entityID: spu.id,
            beforeJSON: "{\"listingStatus\":\"\(beforeStatus)\"}",
            afterJSON: "{\"listingStatus\":\"\(spu.listingStatus)\",\"pendingDelist\":\(spu.pendingDelist)}",
            context: context
        )
        try context.save()
    }

    private func requireReviewer(_ user: User) throws {
        if user.role != Role.reviewer.rawValue && user.role != Role.admin.rawValue {
            throw ProductError.insufficientPermissions
        }
    }

    private func requireContentManagerOrAdmin(_ user: User) throws {
        if user.role != Role.contentManager.rawValue && user.role != Role.admin.rawValue {
            throw ProductError.insufficientPermissions
        }
    }
}
