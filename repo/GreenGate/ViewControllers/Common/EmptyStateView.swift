import UIKit

/// Centered empty state: SF Symbol icon + title + subtitle + optional CTA button.
final class EmptyStateView: UIView {

    // MARK: - Subviews

    private let iconView    = UIImageView()
    private let titleLabel  = UILabel()
    private let subtitleLabel = UILabel()
    private let ctaButton   = UIButton(type: .system)

    var onCTATapped: (() -> Void)?

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
        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, subtitleLabel, ctaButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(8, after: titleLabel)
        stack.setCustomSpacing(20, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
        ])

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor(named: "TextTertiary")
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
        ])

        titleLabel.font = UIFont.preferredFont(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.textColor = UIColor(named: "TextPrimary")

        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textColor = UIColor(named: "TextSecondary")

        ctaButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        ctaButton.titleLabel?.adjustsFontForContentSizeCategory = true
        ctaButton.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)

        ctaButton.layer.cornerRadius = 10
        ctaButton.backgroundColor = UIColor(named: "GreenPrimary")
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 24, bottom: 10, right: 24)
    }

    // MARK: - Configuration

    func configure(
        systemImage: String,
        title: String,
        subtitle: String,
        ctaTitle: String? = nil
    ) {
        iconView.image = UIImage(systemName: systemImage, withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .light))
        titleLabel.text = title
        subtitleLabel.text = subtitle

        if let cta = ctaTitle {
            ctaButton.setTitle(cta, for: .normal)
            ctaButton.isHidden = false
        } else {
            ctaButton.isHidden = true
        }

        accessibilityLabel = "\(title). \(subtitle)"
    }

    // MARK: - Actions

    @objc private func ctaTapped() {
        onCTATapped?()
    }
}
