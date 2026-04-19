import Foundation

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidCredentials
    case accountLocked(until: Date)
    case accountDeactivated
    case biometricNotAvailable
    case biometricFailed
    case sessionExpired
    case insufficientPermissions
    case passwordTooWeak
    case usernameTaken
    case userNotFound

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid username or password."
        case .accountLocked(let until):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Account locked until \(formatter.string(from: until))."
        case .accountDeactivated:
            return "This account has been deactivated."
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device."
        case .biometricFailed:
            return "Biometric authentication failed."
        case .sessionExpired:
            return "Your session has expired. Please log in again."
        case .insufficientPermissions:
            return "You do not have permission to perform this action."
        case .passwordTooWeak:
            return "Password must be at least 8 characters and contain at least 1 number."
        case .usernameTaken:
            return "That username is already taken."
        case .userNotFound:
            return "User not found."
        }
    }
}

// MARK: - POS Errors

enum POSError: LocalizedError {
    case barcodeNotFound(String)
    case skuInactive
    case insufficientInventory(available: Int32)
    case discountExceedsCap(maxPercent: Int)
    case couponNotFound
    case couponExpired
    case couponExhausted
    case couponNotYetValid
    case orderNotFound
    case orderNotOpen
    case orderAlreadyCompleted
    case returnPeriodExpired
    case splitTenderMismatch(expected: Int64, received: Int64)
    case staleRecord
    case parkedTicketExpired

    var errorDescription: String? {
        switch self {
        case .barcodeNotFound(let code):
            return "No product found for barcode: \(code)."
        case .skuInactive:
            return "This product is no longer available."
        case .insufficientInventory(let available):
            return "Insufficient inventory. Only \(available) unit(s) available."
        case .discountExceedsCap(let max):
            return "Discount cannot exceed \(max)%."
        case .couponNotFound:
            return "Coupon code not found."
        case .couponExpired:
            return "This coupon has expired."
        case .couponExhausted:
            return "This coupon has reached its maximum uses."
        case .couponNotYetValid:
            return "This coupon is not yet valid."
        case .orderNotFound:
            return "Order not found."
        case .orderNotOpen:
            return "This order cannot be modified in its current state."
        case .orderAlreadyCompleted:
            return "This order has already been completed."
        case .returnPeriodExpired:
            return "Returns are not accepted past 30 days from the original purchase date."
        case .splitTenderMismatch(let expected, let received):
            return "Payment total (\(received)¢) does not match order total (\(expected)¢)."
        case .staleRecord:
            return "This record was modified by another process. Please refresh and try again."
        case .parkedTicketExpired:
            return "This parked order has expired and has been voided."
        }
    }
}

// MARK: - Ticket Errors

enum TicketError: LocalizedError {
    case ticketNotFound
    case signatureInvalid
    case outsideValidityWindow
    case alreadyUsed(scannedBy: String, scannedAt: Date)
    case ticketVoided
    case ticketExpired
    case eventNotOnSale
    case eventSoldOut
    case capacityExceeded

    var errorDescription: String? {
        switch self {
        case .ticketNotFound:
            return "Ticket not found."
        case .signatureInvalid:
            return "Invalid ticket. This ticket may be counterfeit."
        case .outsideValidityWindow:
            return "Ticket cannot be used outside the event window."
        case .alreadyUsed(let name, let at):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "Already checked in by \(name) at \(formatter.string(from: at))."
        case .ticketVoided:
            return "This ticket has been voided."
        case .ticketExpired:
            return "This ticket has expired."
        case .eventNotOnSale:
            return "This event is not currently on sale."
        case .eventSoldOut:
            return "This event is sold out."
        case .capacityExceeded:
            return "Event capacity has been reached."
        }
    }
}

// MARK: - Property Errors

enum PropertyError: LocalizedError {
    case listingNotFound
    case invalidStatusTransition(from: String, to: String)
    case lockedListing
    case invalidUSState
    case invalidZipCode
    case futureDateRequired
    case changeHistoryUnavailable

    var errorDescription: String? {
        switch self {
        case .listingNotFound:
            return "Property listing not found."
        case .invalidStatusTransition(let from, let to):
            return "Cannot transition property from \(from) to \(to)."
        case .lockedListing:
            return "This listing is locked and cannot be modified."
        case .invalidUSState:
            return "Please enter a valid 2-letter US state code."
        case .invalidZipCode:
            return "Please enter a valid 5-digit or 5+4 ZIP code."
        case .futureDateRequired:
            return "Available from date must be today or in the future."
        case .changeHistoryUnavailable:
            return "Change history is not available for this listing."
        }
    }
}

// MARK: - Import Errors

enum ImportError: LocalizedError {
    case unsupportedFileType
    case fileTooLarge(maxBytes: Int64)
    case parseFailure(reason: String)
    case qualityScoreTooLow(row: Int, score: Int)
    case duplicateBarcode(barcode: String, row: Int)
    case missingRequiredField(field: String, row: Int)
    case invalidFieldValue(field: String, value: String, row: Int)
    case importCancelled
    case noValidRows

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Unsupported file type. Please use CSV or Excel files."
        case .fileTooLarge(let max):
            return "File exceeds the maximum allowed size of \(max / (1024 * 1024)) MB."
        case .parseFailure(let reason):
            return "Failed to parse file: \(reason)."
        case .qualityScoreTooLow(let row, let score):
            return "Row \(row) quality score \(score)/100 is below the minimum threshold of 70."
        case .duplicateBarcode(let barcode, let row):
            return "Row \(row): Barcode '\(barcode)' already exists."
        case .missingRequiredField(let field, let row):
            return "Row \(row): Required field '\(field)' is missing."
        case .invalidFieldValue(let field, let value, let row):
            return "Row \(row): Invalid value '\(value)' for field '\(field)'."
        case .importCancelled:
            return "Import was cancelled."
        case .noValidRows:
            return "No valid rows found in the import file."
        }
    }
}

// MARK: - Attachment Errors

enum AttachmentError: LocalizedError {
    case unsupportedMimeType
    case magicBytesMismatch
    case fileTooLarge
    case duplicateAttachment
    case compressionFailed
    case thumbnailFailed
    case quotaExceeded
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .unsupportedMimeType:
            return "Unsupported file type."
        case .magicBytesMismatch:
            return "File content does not match its extension."
        case .fileTooLarge:
            return "File exceeds the maximum allowed size."
        case .duplicateAttachment:
            return "This file has already been attached (duplicate checksum)."
        case .compressionFailed:
            return "Failed to compress the image."
        case .thumbnailFailed:
            return "Failed to generate thumbnail."
        case .quotaExceeded:
            return "Storage quota exceeded."
        case .fileNotFound:
            return "Attachment file not found in the app sandbox."
        }
    }
}

// MARK: - Core Data Errors

enum CoreDataError: LocalizedError {
    case staleRecord(entityType: String)
    case saveFailed(underlying: Error)
    case fetchFailed(underlying: Error)
    case entityNotFound(entityType: String, id: UUID)

    var errorDescription: String? {
        switch self {
        case .staleRecord(let type):
            return "The \(type) record was modified concurrently. Please refresh and try again."
        case .saveFailed(let error):
            return "Failed to save: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch data: \(error.localizedDescription)"
        case .entityNotFound(let type, let id):
            return "\(type) with ID \(id) not found."
        }
    }
}
