import UIKit
import CoreData

/// Return flow: look up an original order by number, pick line items to
/// return, confirm. Delegates to POSService.processReturn (POS-10).
final class ReturnExchangeViewController: UIViewController {

    private let orderNumberField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let service: POSService
    private var original: Order?
    private var selectedQty: [UUID: Int16] = [:]

    init(service: POSService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Return / Exchange"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Refund", style: .done, target: self, action: #selector(refundTapped)
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
        setupLayout()
    }

    private func setupLayout() {
        let searchContainer = UIView()
        searchContainer.backgroundColor = UIColor(named: "SurfaceElevated")
        searchContainer.layer.cornerRadius = 10
        searchContainer.translatesAutoresizingMaskIntoConstraints = false

        orderNumberField.placeholder = "Enter order number (e.g. GG-20260415-0001)"
        orderNumberField.font = UIFont.preferredFont(forTextStyle: .body)
        orderNumberField.adjustsFontForContentSizeCategory = true
        orderNumberField.clearButtonMode = .whileEditing
        orderNumberField.returnKeyType = .search
        orderNumberField.translatesAutoresizingMaskIntoConstraints = false
        orderNumberField.addTarget(self, action: #selector(searchOrder), for: .primaryActionTriggered)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        view.addSubview(searchContainer)
        searchContainer.addSubview(orderNumberField)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            searchContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            searchContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            orderNumberField.topAnchor.constraint(equalTo: searchContainer.topAnchor, constant: 12),
            orderNumberField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: -12),
            orderNumberField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 16),
            orderNumberField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    @objc private func searchOrder() {
        view.endEditing(true)
        let number = orderNumberField.text ?? ""
        let repo = OrderRepository(context: CoreDataStack.shared.viewContext)
        do {
            original = try repo.fetch(orderNumber: number)
            if original == nil { showError("Order not found.") }
            selectedQty.removeAll()
            tableView.reloadData()
            navigationItem.rightBarButtonItem?.isEnabled = original != nil
        } catch { showError(error.localizedDescription) }
    }

    @objc private func refundTapped() {
        guard let original = original else { return }
        guard let actor = AuthService.shared.currentUser else {
            showError("You must be logged in to process a return.")
            return
        }
        let items = selectedQty
            .filter { $0.value > 0 }
            .map { POSService.ReturnItem(originalLineItemID: $0.key, quantity: $0.value) }
        guard !items.isEmpty else { showError("Select at least one item."); return }
        AuthService.shared.biometricAuth(reason: "Confirm return to process refund") { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success = result else { return }
                do {
                    _ = try self.service.processReturn(
                        originalOrderNumber: original.orderNumber,
                        items: items,
                        actor: actor
                    )
                    self.navigationController?.popViewController(animated: true)
                } catch { self.showError(error.localizedDescription) }
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension ReturnExchangeViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        original?.lineItemsArray.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        guard let line = original?.lineItemsArray[indexPath.row] else { return cell }
        var config = cell.defaultContentConfiguration()
        config.text = line.sku?.barcode ?? "—"
        let picked = selectedQty[line.id] ?? 0
        config.secondaryText =
            "Qty \(line.quantity) · \(CurrencyFormatter.string(fromCents: line.lineTotalCents)) · Returning \(picked)"
        cell.contentConfiguration = config
        cell.accessoryType = picked > 0 ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let line = original?.lineItemsArray[indexPath.row] else { return }
        // Tap cycles return qty 0 → 1 → … → original → 0.
        let current = selectedQty[line.id] ?? 0
        let next = current >= line.quantity ? 0 : current + 1
        selectedQty[line.id] = next
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}
