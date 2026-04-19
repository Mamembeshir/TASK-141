import UIKit
import CoreData

/// Listings table: title, address, rent, sqft, status badge.
final class PropertyListViewController: UIViewController {

    private let tableView  = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyState = EmptyStateView()
    private(set) var fetchedRC: NSFetchedResultsController<PropertyListing>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Properties"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        setupNavigationBar()
        setupTableView()
        setupEmptyState()
        setupFRC()
    }

    private func setupNavigationBar() {
        navigationItem.largeTitleDisplayMode = .always
        let add = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        navigationItem.rightBarButtonItem = add
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(PropertyListCell.self, forCellReuseIdentifier: "PropertyCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.isHidden = true
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])
        emptyState.configure(systemImage: "building.2", title: "No Listings",
                              subtitle: "Add your first property listing.", ctaTitle: "Add Listing")
        emptyState.onCTATapped = { [weak self] in self?.addTapped() }
    }

    private func setupFRC() {
        let fetch = NSFetchRequest<PropertyListing>(entityName: "PropertyListing")
        fetch.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        fetchedRC = NSFetchedResultsController(
            fetchRequest: fetch,
            managedObjectContext: CoreDataStack.shared.viewContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        fetchedRC?.delegate = self
        try? fetchedRC?.performFetch()
        updateEmptyState()
    }

    private func updateEmptyState() {
        let empty = (fetchedRC?.fetchedObjects?.isEmpty) ?? true
        tableView.isHidden = empty
        emptyState.isHidden = !empty
    }

    @objc private func addTapped() {
        let vc = PropertyFormViewController(listing: nil)
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension PropertyListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fetchedRC?.fetchedObjects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PropertyCell", for: indexPath) as! PropertyListCell
        if let listing = fetchedRC?.object(at: indexPath) {
            cell.configure(with: listing)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let listing = fetchedRC?.object(at: indexPath) else { return }
        let detail = PropertyDetailViewController(listing: listing)
        navigationController?.pushViewController(detail, animated: true)
    }
}

extension PropertyListViewController: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.reloadData()
        updateEmptyState()
    }
}

// MARK: - Cell

final class PropertyListCell: UITableViewCell {

    let titleLabel   = UILabel()
    let addressLabel = UILabel()
    let rentLabel    = UILabel()
    let badge        = StatusBadgeView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        for v in [titleLabel, addressLabel, rentLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.adjustsFontForContentSizeCategory = true
            contentView.addSubview(v)
        }
        titleLabel.font   = UIFont.preferredFont(forTextStyle: .headline)
        addressLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        rentLabel.font    = UIFont.preferredFont(forTextStyle: .footnote)
        addressLabel.textColor = UIColor(named: "TextSecondary")
        rentLabel.textColor    = UIColor(named: "TextSecondary")

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.setContentHuggingPriority(.required, for: .horizontal)
        contentView.addSubview(badge)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),

            addressLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            addressLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            rentLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            rentLabel.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: 2),
            rentLabel.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),

            badge.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            badge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with listing: PropertyListing) {
        titleLabel.text = listing.title
        addressLabel.text = "\(listing.addressLine1) · \(listing.city), \(listing.state) \(listing.zipCode)"
        rentLabel.text = "\(CurrencyFormatter.string(fromCents: listing.rentCents))/mo · \(listing.squareFootage) sq ft"
        let status = PropertyStatus(rawValue: listing.status)?.displayName ?? listing.status
        badge.configure(status: status)
    }
}
