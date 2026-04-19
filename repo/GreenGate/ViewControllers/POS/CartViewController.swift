import UIKit
import CoreData

/// Cart list with line items, per-item discount action, coupon entry, and
/// subtotal/discount/tax/total footer. Embedded inside POSViewController.
final class CartViewController: UIViewController {

    private let tableView  = UITableView(frame: .zero, style: .insetGrouped)
    private let couponField = UITextField()
    private let service: POSService
    private var order: Order?

    /// Fires after every cart mutation so the parent can update its large total.
    var onTotalsChanged: ((Order) -> Void)?

    init(service: POSService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "POSCartBackground")
        setupTableView()
    }

    func set(order: Order) {
        self.order = order
        reload()
    }

    func reload() {
        tableView.reloadData()
        if let o = order { onTotalsChanged?(o) }
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(LineItemCell.self, forCellReuseIdentifier: "LineItemCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TotalsCell")
        tableView.register(CouponCell.self, forCellReuseIdentifier: "CouponCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    // MARK: - Line actions

    private func showOrderDiscount() {
        guard let orderID = order?.id else { return }
        let alert = UIAlertController(title: "Order Discount %",
                                      message: "Enter a whole percent (0–30)",
                                      preferredStyle: .alert)
        alert.addTextField { $0.keyboardType = .numberPad; $0.placeholder = "0" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self] _ in
            guard let self else { return }
            let pct = Int(alert.textFields?.first?.text ?? "") ?? 0
            do {
                try self.service.applyOrderDiscount(orderID: orderID, percent: pct)
                self.reload()
            } catch { self.showError(error.localizedDescription) }
        })
        present(alert, animated: true)
    }

    private func showItemDiscount(for line: OrderLineItem) {
        guard let orderID = order?.id else { return }
        let alert = UIAlertController(title: "Discount %", message: "Up to 30%", preferredStyle: .alert)
        alert.addTextField { $0.keyboardType = .numberPad; $0.placeholder = "0" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let pct = Int(alert.textFields?.first?.text ?? "") ?? 0
            do {
                try self.service.applyItemDiscount(lineItemID: line.id, orderID: orderID, percent: pct)
                self.reload()
            } catch { self.showError(error.localizedDescription) }
        })
        present(alert, animated: true)
    }

    private func removeLine(_ line: OrderLineItem) {
        guard let orderID = order?.id else { return }
        try? service.removeLineItem(lineItemID: line.id, orderID: orderID)
        reload()
    }

    fileprivate func stepQuantity(_ line: OrderLineItem, delta: Int16) {
        guard let orderID = order?.id, let skuID = line.sku?.id else { return }
        do {
            if delta > 0 {
                try service.addToCart(orderID: orderID, skuID: skuID, quantity: delta)
            } else if delta < 0 {
                if line.quantity + delta <= 0 {
                    try service.removeLineItem(lineItemID: line.id, orderID: orderID)
                } else {
                    line.quantity += delta
                    line.lineTotalCents = Int64(line.quantity) * line.unitPriceCents - line.discountCents
                    _ = try service.calculateTotals(orderID: orderID)
                }
            }
            reload()
        } catch { showError(error.localizedDescription) }
    }

    fileprivate func applyCoupon(_ code: String) {
        guard let orderID = order?.id else { return }
        do {
            try service.applyCoupon(orderID: orderID, code: code)
            reload()
        } catch { showError(error.localizedDescription) }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension CartViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Items"
        case 1: return "Promotions"
        case 2: return "Totals"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return max(order?.lineItemsArray.count ?? 0, 1)
        case 1: return 2  // row 0 = coupon, row 1 = order discount
        case 2: return 4
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LineItemCell", for: indexPath) as! LineItemCell
            if let line = order?.lineItemsArray[safe: indexPath.row] {
                cell.configure(with: line, onStep: { [weak self] delta in self?.stepQuantity(line, delta: delta) })
            } else {
                cell.configureEmpty()
            }
            return cell
        case 1:
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "CouponCell", for: indexPath) as! CouponCell
                cell.onApply = { [weak self] code in self?.applyCoupon(code) }
                cell.currentCode = order?.couponCode
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "TotalsCell", for: indexPath)
                var config = cell.defaultContentConfiguration()
                let pct = order?.orderDiscountPercent ?? 0
                config.text = "Order Discount"
                config.secondaryText = pct > 0 ? "\(pct)% applied — tap to change" : "Tap to set %"
                cell.contentConfiguration = config
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TotalsCell", for: indexPath)
            var config = cell.defaultContentConfiguration()
            let o = order
            switch indexPath.row {
            case 0:
                config.text = "Subtotal"
                config.secondaryText = CurrencyFormatter.string(fromCents: o?.subtotalCents ?? 0)
            case 1:
                config.text = "Discount"
                config.secondaryText = CurrencyFormatter.string(fromCents: -(o?.discountCents ?? 0))
            case 2:
                config.text = "Tax"
                config.secondaryText = CurrencyFormatter.string(fromCents: o?.taxCents ?? 0)
            case 3:
                config.text = "Total"
                config.secondaryText = CurrencyFormatter.string(fromCents: o?.totalCents ?? 0)
                config.textProperties.font = UIFont.preferredFont(forTextStyle: .headline)
                config.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .headline)
            default: break
            }
            cell.contentConfiguration = config
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0, let line = order?.lineItemsArray[safe: indexPath.row] {
            showItemDiscount(for: line)
        } else if indexPath.section == 1 && indexPath.row == 1 {
            showOrderDiscount()
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        guard indexPath.section == 0, let line = order?.lineItemsArray[safe: indexPath.row] else { return nil }
        let remove = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
            self?.removeLine(line); done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }
}

// MARK: - Cells

final class LineItemCell: UITableViewCell {

    private let name = UILabel()
    private let totalLabel = UILabel()
    private let minus = UIButton(type: .system)
    private let plus = UIButton(type: .system)
    private let qty = UILabel()
    private var onStep: ((Int16) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        [name, totalLabel, qty].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.adjustsFontForContentSizeCategory = true
            contentView.addSubview($0)
        }
        name.font = UIFont.preferredFont(forTextStyle: .body)
        totalLabel.font = UIFont.preferredFont(forTextStyle: .body)
        qty.font = UIFont.preferredFont(forTextStyle: .body)
        qty.textAlignment = .center

        minus.setTitle("−", for: .normal)
        plus.setTitle("+", for: .normal)
        for b in [minus, plus] {
            b.titleLabel?.font = UIFont.preferredFont(forTextStyle: .title3)
            b.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(b)
        }
        minus.addTarget(self, action: #selector(minusTapped), for: .touchUpInside)
        plus.addTarget(self, action: #selector(plusTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            name.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            name.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),

            minus.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 8),
            minus.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            minus.widthAnchor.constraint(equalToConstant: 36),

            qty.leadingAnchor.constraint(equalTo: minus.trailingAnchor, constant: 4),
            qty.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            qty.widthAnchor.constraint(equalToConstant: 28),

            plus.leadingAnchor.constraint(equalTo: qty.trailingAnchor, constant: 4),
            plus.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            plus.widthAnchor.constraint(equalToConstant: 36),

            totalLabel.leadingAnchor.constraint(equalTo: plus.trailingAnchor, constant: 12),
            totalLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            totalLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with line: OrderLineItem, onStep: @escaping (Int16) -> Void) {
        name.text = line.sku?.barcode ?? "—"
        qty.text = "\(line.quantity)"
        totalLabel.text = CurrencyFormatter.string(fromCents: line.lineTotalCents)
        self.onStep = onStep
    }

    func configureEmpty() {
        name.text = "Cart is empty — scan a barcode"
        qty.text = ""
        totalLabel.text = ""
        onStep = nil
    }

    @objc private func minusTapped() { onStep?(-1) }
    @objc private func plusTapped()  { onStep?(1) }
}

final class CouponCell: UITableViewCell {
    private let field = UITextField()
    private let applyBtn = UIButton(type: .system)
    var onApply: ((String) -> Void)?

    var currentCode: String? {
        didSet {
            if let c = currentCode { field.text = c }
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        field.placeholder = "Coupon code"
        field.borderStyle = .roundedRect
        field.translatesAutoresizingMaskIntoConstraints = false
        applyBtn.setTitle("Apply", for: .normal)
        applyBtn.translatesAutoresizingMaskIntoConstraints = false
        applyBtn.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)
        contentView.addSubview(field)
        contentView.addSubview(applyBtn)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            field.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            field.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            applyBtn.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 8),
            applyBtn.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            applyBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func applyTapped() {
        guard let code = field.text, !code.isEmpty else { return }
        onApply?(code)
    }
}

// Safe-index helper — scoped here to avoid collisions.
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
