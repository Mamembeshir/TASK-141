import UIKit
import CoreData

/// Per-SKU inventory view: shows lot history and hosts the stock-adjustment
/// form (SKU picker pre-filled, quantity, reason).
final class InventoryViewController: UIViewController {

    private let sku: ProductSKU
    private let service: InventoryService
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var fetchedRC: NSFetchedResultsController<InventoryLot>?

    init(sku: ProductSKU, service: InventoryService = .shared) {
        self.sku = sku
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Inventory — \(sku.barcode)"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Adjust", style: .plain, target: self, action: #selector(adjustTapped)
        )
        setupTableView()
        setupFRC()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LotCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func setupFRC() {
        let fetch = NSFetchRequest<InventoryLot>(entityName: "InventoryLot")
        fetch.predicate = NSPredicate(format: "sku == %@", sku)
        fetch.sortDescriptors = [NSSortDescriptor(key: "lotDate", ascending: false)]
        fetchedRC = NSFetchedResultsController(
            fetchRequest: fetch,
            managedObjectContext: CoreDataStack.shared.viewContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        fetchedRC?.delegate = self
        try? fetchedRC?.performFetch()
    }

    @objc private func adjustTapped() {
        let alert = UIAlertController(title: "Adjust Stock",
                                      message: "SKU \(sku.barcode)\nAvailable: \(sku.availableCount)",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Quantity (+/-)"
            tf.keyboardType = .numbersAndPunctuation
        }
        alert.addTextField { tf in
            tf.placeholder = "Reason"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { _ in
            let qtyText = alert.textFields?[0].text ?? ""
            let reason  = alert.textFields?[1].text ?? ""
            guard let qty = Int32(qtyText) else {
                self.showError("Quantity must be a whole number."); return
            }
            guard let currentUser = AuthService.shared.currentUser else {
                self.showError("You must be signed in to adjust inventory."); return
            }
            do {
                try self.service.adjustStock(skuID: self.sku.id, quantity: qty,
                                             reason: reason, actorID: currentUser.id)
                self.tableView.reloadData()
            } catch {
                self.showError(error.localizedDescription)
            }
        })
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension InventoryViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fetchedRC?.fetchedObjects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LotCell", for: indexPath)
        guard let lot = fetchedRC?.object(at: indexPath) else { return cell }
        var config = cell.defaultContentConfiguration()
        config.text = DateFormatters.shortDate.string(from: lot.lotDate)
        config.secondaryText = "On hand: \(lot.onHand)  Reserved: \(lot.reservedCount)  Available: \(lot.available)"
        cell.contentConfiguration = config
        return cell
    }
}

extension InventoryViewController: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.reloadData()
    }
}
