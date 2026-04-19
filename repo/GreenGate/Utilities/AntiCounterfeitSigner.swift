import Foundation
import CryptoKit

/// HMAC-SHA256 signing and verification for e-tickets.
/// Signing key is stored in Keychain and generated on first launch.
enum AntiCounterfeitSigner {

    // MARK: - QR Payload Construction

    /// Builds the QR payload string and its HMAC signature.
    /// Format: "ticketNumber|eventID|validFrom_ISO|validTo_ISO|signature"
    static func buildPayload(
        ticketNumber: String,
        eventID: UUID,
        validFrom: Date,
        validTo: Date
    ) -> (payload: String, signature: String) {
        let components = [
            ticketNumber,
            eventID.uuidString,
            DateFormatters.iso8601.string(from: validFrom),
            DateFormatters.iso8601.string(from: validTo),
        ]
        let message = components.joined(separator: "|")
        let signature = sign(message: message)
        let payload = message + "|" + signature
        return (payload, signature)
    }

    // MARK: - Verification

    /// Verifies the QR payload extracted from a scanned ticket.
    /// Returns the extracted fields if valid, throws TicketError.signatureInvalid if not.
    static func verify(qrPayload: String) throws -> QRComponents {
        let parts = qrPayload.components(separatedBy: "|")
        guard parts.count == 5 else { throw TicketError.signatureInvalid }

        let ticketNumber = parts[0]
        let eventIDStr   = parts[1]
        let validFromStr = parts[2]
        let validToStr   = parts[3]
        let signature    = parts[4]

        guard let eventID   = UUID(uuidString: eventIDStr),
              let validFrom = DateFormatters.iso8601.date(from: validFromStr),
              let validTo   = DateFormatters.iso8601.date(from: validToStr) else {
            throw TicketError.signatureInvalid
        }

        let message = [ticketNumber, eventIDStr, validFromStr, validToStr].joined(separator: "|")
        let expectedSig = sign(message: message)

        guard expectedSig == signature else { throw TicketError.signatureInvalid }

        return QRComponents(
            ticketNumber: ticketNumber,
            eventID: eventID,
            validFrom: validFrom,
            validTo: validTo
        )
    }

    // MARK: - Private

    private static func sign(message: String) -> String {
        let keyData = KeychainHelper.shared.ticketSigningKey
        let key = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: key
        )
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - QR Components

    struct QRComponents {
        let ticketNumber: String
        let eventID: UUID
        let validFrom: Date
        let validTo: Date
    }
}
