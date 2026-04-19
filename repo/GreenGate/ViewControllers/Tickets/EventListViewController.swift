import UIKit
import CoreData

/// Events table: name, date, sold/checked-in counts, status badge.
final class EventListViewController: UIViewController {

    private let tableView  = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyState = EmptyStateView()
    private(set) var fetchedRC: NSFetchedResultsController<TicketEvent>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Events"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        setupNavigationBar()
        setupTableView()
        setupEmptyState()
        setupFRC()
    }

    private func setupNavigationBar() {
        navigationItem.largeTitleDisplayMode = .always
        let add = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        let scan = UIBarButtonItem(image: UIImage(systemName: "qrcode.viewfinder"),
                                   style: .plain, target: self, action: #selector(scanTapped))
        navigationItem.rightBarButtonItems = [add, scan]
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(EventListCell.self, forCellReuseIdentifier: "EventCell")
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
        emptyState.configure(systemImage: "ticket", title: "No Events",
                              subtitle: "Create your first event to start selling tickets.",
                              ctaTitle: "New Event")
        emptyState.onCTATapped = { [weak self] in self?.addTapped() }
    }

    private func setupFRC() {
        let fetch = NSFetchRequest<TicketEvent>(entityName: "TicketEvent")
        fetch.sortDescriptors = [NSSortDescriptor(key: "eventDate", ascending: true)]
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
        let vc = EventDetailViewController(event: nil)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func scanTapped() {
        let scanner = TicketScannerViewController()
        navigationController?.pushViewController(scanner, animated: true)
    }
}

extension EventListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fetchedRC?.fetchedObjects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "EventCell", for: indexPath) as! EventListCell
        if let event = fetchedRC?.object(at: indexPath) {
            cell.configure(with: event)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let event = fetchedRC?.object(at: indexPath) else { return }
        let detail = EventDetailViewController(event: event)
        navigationController?.pushViewController(detail, animated: true)
    }
}

extension EventListViewController: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.reloadData()
        updateEmptyState()
    }
}

// MARK: - Cell

final class EventListCell: UITableViewCell {

    let nameLabel    = UILabel()
    let dateLabel    = UILabel()
    let countsLabel  = UILabel()
    let badge        = StatusBadgeView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        for v in [nameLabel, dateLabel, countsLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.adjustsFontForContentSizeCategory = true
            contentView.addSubview(v)
        }
        nameLabel.font   = UIFont.preferredFont(forTextStyle: .headline)
        dateLabel.font   = UIFont.preferredFont(forTextStyle: .footnote)
        countsLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        dateLabel.textColor   = UIColor(named: "TextSecondary")
        countsLabel.textColor = UIColor(named: "TextSecondary")

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.setContentHuggingPriority(.required, for: .horizontal)
        contentView.addSubview(badge)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            nameLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),

            dateLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            dateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            countsLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            countsLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 2),
            countsLabel.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),

            badge.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            badge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with event: TicketEvent) {
        nameLabel.text = event.name
        dateLabel.text = "\(DateFormatters.shortDate.string(from: event.eventDate)) · Capacity \(event.totalCapacity)"
        countsLabel.text = "Sold \(event.soldCount) · Checked in \(event.checkedInCount)"
        let status = EventStatus(rawValue: event.status)?.displayName ?? event.status
        badge.configure(status: status)
    }
}
