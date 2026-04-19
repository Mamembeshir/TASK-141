import Foundation

enum MaskingHelper {

    /// Masks a phone number, showing only the last 4 digits. e.g. "***-***-1234"
    static func maskPhone(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 4 else { return "***-***-****" }
        let last4 = String(digits.suffix(4))
        return "***-***-\(last4)"
    }

    /// Masks an email, showing only the domain. e.g. "***@example.com"
    static func maskEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return "***@***" }
        return "***@\(parts[1])"
    }

    /// Masks an SSN, showing only the last 4 digits. e.g. "***-**-1234"
    static func maskSSN(_ ssn: String) -> String {
        let digits = ssn.filter { $0.isNumber }
        guard digits.count >= 4 else { return "***-**-****" }
        let last4 = String(digits.suffix(4))
        return "***-**-\(last4)"
    }

    /// Masks a string to show only the last N characters. e.g. "****4242"
    static func maskLast(_ string: String, showLast n: Int, maskChar: Character = "*") -> String {
        guard string.count > n else { return string }
        let visible = String(string.suffix(n))
        let masked  = String(repeating: maskChar, count: string.count - n)
        return masked + visible
    }

    /// Masks a credit card, showing only last 4. e.g. "**** **** **** 4242"
    static func maskCardNumber(_ number: String) -> String {
        let digits = number.filter { $0.isNumber }
        guard digits.count >= 4 else { return "**** **** **** ****" }
        let last4 = String(digits.suffix(4))
        return "**** **** **** \(last4)"
    }
}
