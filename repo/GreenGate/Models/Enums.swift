import Foundation

// MARK: - Auth & Users

enum Role: String, CaseIterable, Codable {
    case admin           = "ADMIN"
    case cashier         = "CASHIER"
    case gateAttendant   = "GATE_ATTENDANT"
    case contentManager  = "CONTENT_MANAGER"
    case reviewer        = "REVIEWER"

    var displayName: String {
        switch self {
        case .admin:          return "Administrator"
        case .cashier:        return "Cashier"
        case .gateAttendant:  return "Gate Attendant"
        case .contentManager: return "Content Manager"
        case .reviewer:       return "Reviewer"
        }
    }
}

// MARK: - App Module Capability Matrix

/// All navigable modules in the app. Used as the single source of truth for
/// role-based access control in both navigation composition (SceneRouter) and
/// the iPad sidebar (SidebarViewController).
enum AppModule: CaseIterable {
    case dashboard
    case products
    case pos
    case tickets
    case properties
    /// Learning content: Content Manager (create/edit), Reviewer (review), Admin.
    case learningContent
    /// Admin-only: user management, audit log, import/export (iPad sidebar).
    case userManagement
    case auditLog
    case importExport
}

extension Role {
    /// Modules this role is permitted to access. Gate Attendant is handled
    /// separately (scanner-only root); its set is intentionally empty here.
    var allowedModules: Set<AppModule> {
        switch self {
        case .admin:
            return Set(AppModule.allCases)
        case .cashier:
            // Cashier scope: POS checkout / returns / shift close only (no Tickets module).
            return [.dashboard, .pos]
        case .contentManager:
            return [.dashboard, .products, .properties, .learningContent]
        case .reviewer:
            return [.dashboard, .products, .properties, .learningContent]
        case .gateAttendant:
            return []
        }
    }
}

enum UserStatus: String, CaseIterable, Codable {
    case active      = "ACTIVE"
    case locked      = "LOCKED"
    case deactivated = "DEACTIVATED"
}

// MARK: - Product Listing

enum ProductListingStatus: String, CaseIterable, Codable {
    case draft             = "DRAFT"
    case pendingApproval   = "PENDING_APPROVAL"
    case listed            = "LISTED"
    case delisted          = "DELISTED"

    var displayName: String {
        switch self {
        case .draft:           return "Draft"
        case .pendingApproval: return "Pending Approval"
        case .listed:          return "Listed"
        case .delisted:        return "Delisted"
        }
    }
}

// MARK: - POS

enum OrderStatus: String, CaseIterable, Codable {
    case open      = "OPEN"
    case parked    = "PARKED"
    case completed = "COMPLETED"
    case returned  = "RETURNED"
    case voided    = "VOIDED"

    var displayName: String {
        switch self {
        case .open:      return "Open"
        case .parked:    return "Parked"
        case .completed: return "Completed"
        case .returned:  return "Returned"
        case .voided:    return "Voided"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .returned, .voided: return true
        default:                 return false
        }
    }
}

enum DiscountType: String, CaseIterable, Codable {
    case percent     = "PERCENT"
    case fixedAmount = "FIXED_AMOUNT"
}

enum DiscountAppliesTo: String, CaseIterable, Codable {
    case item  = "ITEM"
    case order = "ORDER"
}

enum PaymentTenderType: String, CaseIterable, Codable {
    case cash        = "CASH"
    case cardOnFile  = "CARD_ON_FILE"
    case split       = "SPLIT"

    var displayName: String {
        switch self {
        case .cash:       return "Cash"
        case .cardOnFile: return "Card on File"
        case .split:      return "Split Tender"
        }
    }
}

// MARK: - E-Ticketing

enum TicketStatus: String, CaseIterable, Codable {
    case valid   = "VALID"
    case used    = "USED"
    case voided  = "VOIDED"
    case expired = "EXPIRED"

    var displayName: String {
        switch self {
        case .valid:   return "Valid"
        case .used:    return "Used"
        case .voided:  return "Voided"
        case .expired: return "Expired"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .used, .voided, .expired: return true
        default:                       return false
        }
    }
}

enum EventStatus: String, CaseIterable, Codable {
    case draft     = "DRAFT"
    case onSale    = "ON_SALE"
    case soldOut   = "SOLD_OUT"
    case closed    = "CLOSED"
    case cancelled = "CANCELLED"

    var displayName: String {
        switch self {
        case .draft:     return "Draft"
        case .onSale:    return "On Sale"
        case .soldOut:   return "Sold Out"
        case .closed:    return "Closed"
        case .cancelled: return "Cancelled"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .closed, .cancelled: return true
        default:                  return false
        }
    }
}

enum CheckInResult: String, CaseIterable, Codable {
    case success   = "SUCCESS"
    case duplicate = "DUPLICATE"
    case invalid   = "INVALID"
    case expired   = "EXPIRED"
}

// MARK: - Properties

enum PropertyStatus: String, CaseIterable, Codable {
    case draft    = "DRAFT"
    case inReview = "IN_REVIEW"
    case published = "PUBLISHED"
    case locked   = "LOCKED"

    var displayName: String {
        switch self {
        case .draft:     return "Draft"
        case .inReview:  return "In Review"
        case .published: return "Published"
        case .locked:    return "Locked"
        }
    }
}

// MARK: - Learning Content

enum LearningContentStatus: String, CaseIterable, Codable {
    case draft     = "DRAFT"
    case published = "PUBLISHED"
    case archived  = "ARCHIVED"

    var displayName: String {
        switch self {
        case .draft:     return "Draft"
        case .published: return "Published"
        case .archived:  return "Archived"
        }
    }
}

// MARK: - Attachments

enum AttachmentParentType: String, CaseIterable, Codable {
    case product  = "PRODUCT"
    case property = "PROPERTY"
    case event    = "EVENT"
    case general  = "GENERAL"
}

enum AttachmentMimeType: String, CaseIterable, Codable {
    case jpeg = "image/jpeg"
    case png  = "image/png"
    case heic = "image/heic"
    case mov  = "video/quicktime"
    case mp4  = "video/mp4"
    case m4a  = "audio/x-m4a"
    case mp3  = "audio/mpeg"
    case pdf  = "application/pdf"

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png:  return "png"
        case .heic: return "heic"
        case .mov:  return "mov"
        case .mp4:  return "mp4"
        case .m4a:  return "m4a"
        case .mp3:  return "mp3"
        case .pdf:  return "pdf"
        }
    }

    var isImage: Bool {
        switch self {
        case .jpeg, .png, .heic: return true
        default:                  return false
        }
    }

    var isVideo: Bool {
        switch self {
        case .mov, .mp4: return true
        default:          return false
        }
    }

    var isAudio: Bool {
        switch self {
        case .m4a, .mp3: return true
        default:          return false
        }
    }
}
