import UIKit
import CoreData

/// Detail view for an SPU: header with status, SKU variants, per-SKU inventory
/// levels, and approval-workflow actions (submit, approve, reject, delist).
final class ProductDetailViewController: UIViewController {

    private let spu: ProductSPU
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let service: ProductService

    init(spu: ProductSPU, service: ProductService = .shared) {
        self.spu = spu
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = spu.name
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        setupNavigationBar()
        setupTableView()
    }

    private func setupNavigationBar() {
        navigationItem.largeTitleDisplayMode = .never
        let edit = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(editTapped))
        let actions = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"),
                                      style: .plain, target: self, action: #selector(actionsTapped))
        navigationItem.rightBarButtonItems = [edit, actions]
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SKUCell")
    }

    @objc private func editTapped() {
        let vc = ProductFormViewController(spu: spu)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func actionsTapped() {
        let alert = UIAlertController(title: "Workflow", message: nil, preferredStyle: .actionSheet)
        let status = ProductListingStatus(rawValue: spu.listingStatus) ?? .draft
        let user = AuthService.shared.currentUser
        let isReviewer = user?.role == Role.reviewer.rawValue || user?.role == Role.admin.rawValue

        switch status {
        case .draft:
            alert.addAction(UIAlertAction(title: "Submit for Approval", style: .default) { _ in
                self.runAction { try self.service.submitForApproval(spuID: self.spu.id, actor: user!) }
            })
        case .pendingApproval where isReviewer:
            alert.addAction(UIAlertAction(title: "Approve", style: .default) { _ in
                self.runAction {
                    if self.spu.pendingDelist {
                        try self.service.approveDelist(spuID: self.spu.id, reviewerID: user!.id, reviewer: user!)
                    } else {
                        try self.service.approve(spuID: self.spu.id, reviewerID: user!.id, reviewer: user!)
                    }
                }
            })
            alert.addAction(UIAlertAction(title: "Reject", style: .destructive) { _ in
                self.promptRejectionNotes(reviewer: user!)
            })
        case .listed:
            alert.addAction(UIAlertAction(title: "Request Delist", style: .destructive) { _ in
                self.runAction { try self.service.requestDelist(spuID: self.spu.id, actor: user!) }
            })
        default:
            break
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func promptRejectionNotes(reviewer: User) {
        let alert = UIAlertController(title: "Reject", message: "Notes for the content manager:",
                                      preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Required" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reject", style: .destructive) { _ in
            let notes = alert.textFields?.first?.text ?? ""
            self.runAction {
                try self.service.reject(spuID: self.spu.id, reviewerID: reviewer.id,
                                        reviewer: reviewer, notes: notes)
            }
        })
        present(alert, animated: true)
    }

    private func runAction(_ block: () throws -> Void) {
        do {
            try block()
            tableView.reloadData()
            title = spu.name
        } catch {
            let alert = UIAlertController(title: "Error",
                                          message: error.localizedDescription,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

extension ProductDetailViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Details"
        case 1: return "SKUs (\(spu.skusArray.count))"
        case 2: return "Inventory"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0, let notes = spu.rejectionNotes, !notes.isEmpty {
            return "Rejection notes: \(notes)"
        }
        return nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 4
        case 1: return max(spu.skusArray.count, 1)
        case 2: return max(spu.skusArray.count, 1)
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuse = indexPath.section == 0 ? "Cell" : "SKUCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuse, for: indexPath)
        var config = cell.defaultContentConfiguration()

        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0: config.text = "Name";     config.secondaryText = spu.name
            case 1: config.text = "Category"; config.secondaryText = spu.category ?? "—"
            case 2:
                config.text = "Listing Status"
                let status = ProductListingStatus(rawValue: spu.listingStatus)?.displayName ?? spu.listingStatus
                let delistSuffix = spu.pendingDelist ? " (delist)" : ""
                config.secondaryText = "\(status)\(delistSuffix)"
            case 3: config.text = "Description"; config.secondaryText = spu.description_ ?? "—"
            default: break
            }
        case 1:
            if spu.skusArray.isEmpty {
                config.text = "No SKUs yet"
                config.textProperties.color = UIColor(named: "TextTertiary") ?? .tertiaryLabel
            } else {
                let sku = spu.skusArray[indexPath.row]
                config.text = sku.barcode
                let wrap = sku.wrapType ?? "—"
                let color = sku.color ?? "—"
                config.secondaryText =
                    "\(sku.stemCount) stems · \(wrap) · \(color) · \(CurrencyFormatter.string(fromCents: sku.priceCents))"
            }
        case 2:
            if spu.skusArray.isEmpty {
                config.text = "—"
            } else {
                let sku = spu.skusArray[indexPath.row]
                let lots = sku.inventoryLotsArray
                let onHand = lots.reduce(0) { $0 + $1.onHand }
                let reserved = lots.reduce(0) { $0 + $1.reservedCount }
                config.text = sku.barcode
                config.secondaryText = "On hand: \(onHand) · Reserved: \(reserved) · Available: \(sku.availableCount)"
            }
        default: break
        }
        cell.contentConfiguration = config
        cell.accessoryType = indexPath.section == 2 && !spu.skusArray.isEmpty
            ? .disclosureIndicator : .none
        return cell
    }
}

extension ProductDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 2, !spu.skusArray.isEmpty else { return }
        let sku = spu.skusArray[indexPath.row]
        let vc = InventoryViewController(sku: sku)
        navigationController?.pushViewController(vc, animated: true)
    }
}
