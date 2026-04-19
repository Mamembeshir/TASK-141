import UIKit

/// Capsule-shaped status badge. Auto-colors based on the status string passed to it.
final class StatusBadgeView: UIView {

    private let label = UILabel()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        layer.masksToBounds = true

        label.font = UIFont.preferredFont(forTextStyle: .caption2).withTraits(.traitBold)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    // MARK: - Configuration

    func configure(status: String) {
        label.text = status
        applyColors(for: status)
        accessibilityLabel = "Status: \(status)"
    }

    // MARK: - Color Mapping

    private func applyColors(for status: String) {
        switch status.uppercased() {

        // Success states
        case OrderStatus.completed.rawValue,
             ProductListingStatus.listed.rawValue,
             PropertyStatus.published.rawValue,
             EventStatus.onSale.rawValue,
             TicketStatus.valid.rawValue,
             UserStatus.active.rawValue,
             CheckInResult.success.rawValue:
            label.textColor = UIColor(named: "Success")
            backgroundColor = UIColor(named: "Success")?.withAlphaComponent(0.15)

        // Warning states
        case ProductListingStatus.pendingApproval.rawValue,
             PropertyStatus.inReview.rawValue,
             OrderStatus.parked.rawValue,
             EventStatus.soldOut.rawValue:
            label.textColor = UIColor(named: "Warning")
            backgroundColor = UIColor(named: "Warning")?.withAlphaComponent(0.15)

        // Danger / terminal states
        case OrderStatus.voided.rawValue,
             OrderStatus.returned.rawValue,
             ProductListingStatus.delisted.rawValue,
             PropertyStatus.locked.rawValue,
             TicketStatus.expired.rawValue,
             TicketStatus.voided.rawValue,
             TicketStatus.used.rawValue,
             EventStatus.cancelled.rawValue,
             EventStatus.closed.rawValue,
             UserStatus.locked.rawValue,
             UserStatus.deactivated.rawValue,
             CheckInResult.duplicate.rawValue,
             CheckInResult.invalid.rawValue,
             CheckInResult.expired.rawValue:
            label.textColor = UIColor(named: "Danger")
            backgroundColor = UIColor(named: "Danger")?.withAlphaComponent(0.15)

        // Draft / neutral states
        default:
            label.textColor = UIColor(named: "TextTertiary")
            backgroundColor = UIColor(named: "SurfaceGrouped")
        }
    }
}

// MARK: - UIFont Helper

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
