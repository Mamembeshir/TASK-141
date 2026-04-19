import UIKit
import CoreData

/// List of PARKED orders. Each row shows the order number, total, and a live
/// countdown to the 30-minute auto-expire. Tap to unpark.
final class ParkedTicketsViewController: UIViewController {

    private let tableView  = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyState = EmptyStateView()
    private var fetchedRC: NSFetchedResultsController<Order>?
    private var timer: Timer?
    private let service: POSService

    init(service: POSService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Parked Orders"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        setupTableView()
        setupEmptyState()
        setupFRC()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate(); timer = nil
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "OrderCell")
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
        emptyState.configure(systemImage: "tray.2", title: "No Parked Orders",
                             subtitle: "Parked orders will appear here for up to 30 minutes.")
    }

    private func setupFRC() {
        let fetch = NSFetchRequest<Order>(entityName: "Order")
        fetch.predicate = NSPredicate(format: "status == %@", OrderStatus.parked.rawValue)
        fetch.sortDescriptors = [NSSortDescriptor(key: "parkedAt", ascending: false)]
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

    static func remainingText(parkedAt: Date) -> String {
        let windowSec = TimeInterval(AppConfiguration.parkedOrderExpiryMinutes * 60)
        let remaining = windowSec - Date().timeIntervalSince(parkedAt)
        if remaining <= 0 { return "Expired" }
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        return String(format: "%d:%02d left", mins, secs)
    }
}

extension ParkedTicketsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fetchedRC?.fetchedObjects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "OrderCell", for: indexPath)
        guard let order = fetchedRC?.object(at: indexPath) else { return cell }
        var config = cell.defaultContentConfiguration()
        config.text = order.orderNumber
        if let parkedAt = order.parkedAt {
            config.secondaryText = "\(Self.remainingText(parkedAt: parkedAt)) · \(CurrencyFormatter.string(fromCents: order.totalCents))"
        }
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let order = fetchedRC?.object(at: indexPath) else { return }
        guard let actor = AuthService.shared.currentUser else {
            let alert = UIAlertController(title: "Error",
                                          message: "You must be signed in to unpark an order.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        do {
            try service.unparkOrder(orderID: order.id, actor: actor)
            navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "Error", message: error.localizedDescription,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

extension ParkedTicketsViewController: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.reloadData()
        updateEmptyState()
    }
}
