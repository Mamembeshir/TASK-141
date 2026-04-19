import UIKit
import CoreData

/// Dashboard — summary tiles for products, orders, events, and listings.
/// Lightweight: fetches only aggregate counts to meet cold-start < 1.5s target.
final class DashboardViewController: UIViewController {

    // MARK: - Subviews

    private let scrollView   = UIScrollView()
    private let contentStack = UIStackView()
    private let emptyState   = EmptyStateView()

    private var tiles: [DashboardTileView] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dashboard"
        view.backgroundColor = UIColor(named: "SurfacePrimary")
        setupLayout()
        loadCounts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadCounts()
    }

    // MARK: - Layout

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.layoutMargins = UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        let tileData: [(String, String, String)] = [
            ("Listed Products",  "leaf.fill",     "GreenPrimary"),
            ("Open Orders",      "cart.fill",     "InfoBlue"),
            ("Today's Events",   "ticket.fill",   "GreenAccent"),
            ("Active Listings",  "building.2.fill","Success"),
        ]

        for (title, icon, color) in tileData {
            let tile = DashboardTileView(title: title, iconName: icon, colorName: color)
            tiles.append(tile)
            contentStack.addArrangedSubview(tile)
        }
    }

    // MARK: - Data

    private func loadCounts() {
        let context = CoreDataStack.shared.viewContext

        let productCount  = fetchCount(entity: "ProductSKU",
                                       predicate: NSPredicate(format: "isActive == YES"),
                                       context: context)
        let orderCount    = fetchCount(entity: "Order",
                                       predicate: NSPredicate(format: "status == %@", OrderStatus.open.rawValue),
                                       context: context)
        let today         = Calendar.current.startOfDay(for: Date())
        let tomorrow      = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let eventCount    = fetchCount(entity: "TicketEvent",
                                       predicate: NSPredicate(format: "eventDate >= %@ AND eventDate < %@",
                                                              today as NSDate, tomorrow as NSDate),
                                       context: context)
        let listingCount  = fetchCount(entity: "PropertyListing",
                                       predicate: NSPredicate(format: "status == %@", PropertyStatus.published.rawValue),
                                       context: context)

        let counts = [productCount, orderCount, eventCount, listingCount]
        for (tile, count) in zip(tiles, counts) {
            tile.count = count
        }
    }

    private func fetchCount(entity: String, predicate: NSPredicate?, context: NSManagedObjectContext) -> Int {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: entity)
        fetch.predicate = predicate
        return (try? context.count(for: fetch)) ?? 0
    }
}

// MARK: - DashboardTileView

final class DashboardTileView: UIView {

    private let iconView   = UIImageView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()

    var count: Int = 0 {
        didSet { countLabel.text = "\(count)" }
    }

    init(title: String, iconName: String, colorName: String) {
        super.init(frame: .zero)
        setup(title: title, iconName: iconName, colorName: colorName)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup(title: String, iconName: String, colorName: String) {
        backgroundColor     = UIColor(named: "SurfaceElevated")
        layer.cornerRadius  = 12
        layer.masksToBounds = false
        layer.shadowColor   = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowOffset  = CGSize(width: 0, height: 2)
        layer.shadowRadius  = 6

        iconView.image = UIImage(systemName: iconName,
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .medium))
        iconView.tintColor = UIColor(named: colorName)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = UIColor(named: "TextSecondary")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.text = "—"
        countLabel.font = UIFontMetrics(forTextStyle: .title1).scaledFont(
            for: UIFont.systemFont(ofSize: 36, weight: .bold)
        )
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = UIColor(named: "TextPrimary")
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            countLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            countLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }
}
