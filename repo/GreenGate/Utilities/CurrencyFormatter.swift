import Foundation

enum CurrencyFormatter {

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle          = .currency
        f.currencyCode         = "USD"
        f.currencySymbol       = "$"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.roundingMode         = .halfEven   // banker's rounding
        return f
    }()

    /// Converts integer cents to a formatted string. e.g. 250000 → "$2,500.00"
    static func string(fromCents cents: Int64) -> String {
        let dollars = Decimal(cents) / 100
        return formatter.string(from: dollars as NSDecimalNumber) ?? "$0.00"
    }

    /// Converts integer cents to a Decimal for display or further calculation.
    static func decimal(fromCents cents: Int64) -> Decimal {
        Decimal(cents) / 100
    }

    /// Converts a Double (dollars) to integer cents using banker's rounding.
    static func cents(fromDollars dollars: Double) -> Int64 {
        var d = Decimal(dollars)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &d, 2, .bankers)
        return Int64((rounded * 100 as Decimal).description.split(separator: ".").first.flatMap { Int64($0) } ?? 0)
    }

    /// Applies tax to a subtotal in cents. Returns the tax amount in cents (banker's rounding).
    static func taxCents(onSubtotal subtotalCents: Int64, rateBasisPoints: Int32) -> Int64 {
        // rateBasisPoints = rate × 1_000_000 (e.g. 88750 = 8.875%)
        // tax = subtotal × rateBasisPoints / 1_000_000
        let result = Decimal(subtotalCents) * Decimal(rateBasisPoints) / Decimal(1_000_000)
        var rounded = Decimal()
        var input = result
        NSDecimalRound(&rounded, &input, 0, .bankers)
        return (rounded as NSDecimalNumber).int64Value
    }
}
