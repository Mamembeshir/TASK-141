import UIKit

/// A UILabel subclass that displays a monetary amount in cents.
/// Automatically formats via CurrencyFormatter.
final class CurrencyLabel: UILabel {

    // MARK: - State

    private var _amountCents: Int64 = 0

    var amountCents: Int64 {
        get { _amountCents }
        set {
            _amountCents = newValue
            text = CurrencyFormatter.string(fromCents: newValue)
            accessibilityLabel = text
        }
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyDefaults()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyDefaults()
    }

    private func applyDefaults() {
        font = UIFont.preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        textColor = UIColor(named: "TextPrimary")
        textAlignment = .right
        text = CurrencyFormatter.string(fromCents: 0)
    }

    // MARK: - Style Presets

    /// Large bold total display for POS cart.
    func applyPOSTotalStyle() {
        font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: UIFont.systemFont(ofSize: 34, weight: .bold)
        )
        textColor = UIColor(named: "POSTotal")
    }

    /// Secondary smaller display for line items.
    func applyLineItemStyle() {
        font = UIFont.preferredFont(forTextStyle: .subheadline)
        textColor = UIColor(named: "TextSecondary")
    }
}
