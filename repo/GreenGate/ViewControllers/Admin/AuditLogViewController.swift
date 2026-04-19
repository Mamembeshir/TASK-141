import UIKit
import CoreData

/// Searchable audit-log browser. Search filters on `entityType`, `action`, or
/// `actorID` substring; entity-type filter via segmented control.
final class AuditLogViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchController = UISearchController(searchResultsController: nil)
    private let filterControl = UISegmentedControl(items: ["All", "Orders", "Products", "Tickets", "Properties"])
    private var fetchedRC: NSFetchedResultsController<AuditLog>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Audit Log"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        setupSearch()
        setupFilter()
        setupTableView()
        rebuildFetch()
    }

    private func setupSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search action / entity / actor"
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }

    private func setupFilter() {
        filterControl.selectedSegmentIndex = 0
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterControl)
        NSLayoutConstraint.activate([
            filterControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            filterControl.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            filterControl.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LogCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    @objc private func filterChanged() { rebuildFetch() }

    private func rebuildFetch() {
        let fetch = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        fetch.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetch.fetchBatchSize = 50

        var predicates: [NSPredicate] = []
        let entityFilter: String? = {
            switch filterControl.selectedSegmentIndex {
            case 1: return "Order"
            case 2: return "Product"
            case 3: return "ETicket"
            case 4: return "Property"
            default: return nil
            }
        }()
        if let prefix = entityFilter {
            predicates.append(NSPredicate(format: "entityType BEGINSWITH %@", prefix))
        }
        if let q = searchController.searchBar.text, !q.isEmpty {
            predicates.append(NSPredicate(
                format: "action CONTAINS[c] %@ OR entityType CONTAINS[c] %@",
                q, q
            ))
        }
        if !predicates.isEmpty {
            fetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        fetchedRC = NSFetchedResultsController(
            fetchRequest: fetch,
            managedObjectContext: CoreDataStack.shared.viewContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        fetchedRC?.delegate = self
        try? fetchedRC?.performFetch()
        tableView.reloadData()
    }
}

extension AuditLogViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        rebuildFetch()
    }
}

extension AuditLogViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fetchedRC?.fetchedObjects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LogCell", for: indexPath)
        guard let log = fetchedRC?.object(at: indexPath) else { return cell }
        var config = cell.defaultContentConfiguration()
        config.text = "\(log.action) · \(log.entityType)"
        config.secondaryText = "\(DateFormatters.shortDateTime.string(from: log.timestamp)) · \(log.actorID.uuidString.prefix(8))"
        cell.contentConfiguration = config
        return cell
    }
}

extension AuditLogViewController: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.reloadData()
    }
}
