import UIKit

/// Tender selection: Cash / Card on File / Split. Amounts entered in cents for
/// simplicity. A "Complete" button finalizes the order.
final class CheckoutViewController: UIViewController {

    enum Mode {
        case cash
        case cardOnFile
        case split
    }

    private let tableView  = UITableView(frame: .zero, style: .insetGrouped)
    private let totalLabel = CurrencyLabel()
    private let order: Order
    private let service: POSService
    private let onComplete: () -> Void

    private var mode: Mode = .cash
    private var cashAmount: Int64 = 0
    private var cardAmount: Int64 = 0
    private let cashField = UITextField()
    private let cardField = UITextField()
    private let cardMemo  = UITextField()

    init(order: Order, service: POSService = .shared, onComplete: @escaping () -> Void = {}) {
        self.order = order
        self.service = service
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Checkout"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never

        _ = try? service.calculateTotals(orderID: order.id)
        totalLabel.amountCents = order.totalCents

        setupLayout()
        setupFields()
    }

    private func setupLayout() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)

        totalLabel.applyPOSTotalStyle()
        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(totalLabel)

        let confirmBtn = UIButton(type: .system)
        confirmBtn.setTitle("Complete", for: .normal)
        confirmBtn.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        confirmBtn.titleLabel?.adjustsFontForContentSizeCategory = true
        confirmBtn.backgroundColor = UIColor(named: "GreenPrimary")
        confirmBtn.setTitleColor(.white, for: .normal)
        confirmBtn.layer.cornerRadius = 10
        confirmBtn.translatesAutoresizingMaskIntoConstraints = false
        confirmBtn.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        confirmBtn.accessibilityLabel = "Complete Payment"
        view.addSubview(confirmBtn)

        NSLayoutConstraint.activate([
            totalLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            totalLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            totalLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: totalLabel.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            confirmBtn.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 16),
            confirmBtn.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            confirmBtn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            confirmBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            confirmBtn.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    private func setupFields() {
        for f in [cashField, cardField, cardMemo] {
            f.borderStyle = .roundedRect
            f.font = UIFont.preferredFont(forTextStyle: .body)
            f.adjustsFontForContentSizeCategory = true
            f.translatesAutoresizingMaskIntoConstraints = false
        }
        cashField.keyboardType = .numberPad
        cardField.keyboardType = .numberPad
        cashField.placeholder = "Cash cents"
        cardField.placeholder = "Card cents"
        cardMemo.placeholder = "Card memo (e.g. Visa …4242)"
        cashField.addTarget(self, action: #selector(amountsChanged), for: .editingChanged)
        cardField.addTarget(self, action: #selector(amountsChanged), for: .editingChanged)
    }

    @objc private func amountsChanged() {
        cashAmount = Int64(cashField.text ?? "") ?? 0
        cardAmount = Int64(cardField.text ?? "") ?? 0
    }

    @objc private func confirmTapped() {
        var payments: [POSService.SplitPayment] = []
        switch mode {
        case .cash:
            payments = [.init(tender: .cash, amountCents: order.totalCents, memo: nil)]
        case .cardOnFile:
            payments = [.init(tender: .cardOnFile, amountCents: order.totalCents,
                              memo: cardMemo.text ?? "Card on file")]
        case .split:
            payments = [
                .init(tender: .cash, amountCents: cashAmount, memo: nil),
                .init(tender: .cardOnFile, amountCents: cardAmount,
                      memo: cardMemo.text ?? "Card on file"),
            ]
        }
        guard let actor = AuthService.shared.currentUser else {
            let alert = UIAlertController(title: "Error",
                                          message: "You must be signed in to complete a sale.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        do {
            try service.splitTender(orderID: order.id, payments: payments)
            try service.completeOrder(orderID: order.id, actor: actor)
            onComplete()
            navigationController?.popToRootViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "Error", message: error.localizedDescription,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

extension CheckoutViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Order Summary" : "Payment Method"
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 4
        case 1:
            switch mode {
            case .cash: return 3
            case .cardOnFile: return 4
            case .split: return 5
            }
        default: return 0
        }
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let (label, value): (String, Int64) = {
                switch indexPath.row {
                case 0: return ("Subtotal", order.subtotalCents)
                case 1: return ("Discount", -order.discountCents)
                case 2: return ("Tax", order.taxCents)
                default: return ("Total", order.totalCents)
                }
            }()
            config.text = label
            config.secondaryText = CurrencyFormatter.string(fromCents: value)
        } else {
            cell.accessoryType = .none
            switch indexPath.row {
            case 0:
                config.text = "Cash"
                cell.accessoryType = mode == .cash ? .checkmark : .none
            case 1:
                config.text = "Card on File"
                cell.accessoryType = mode == .cardOnFile ? .checkmark : .none
            case 2:
                config.text = "Split"
                cell.accessoryType = mode == .split ? .checkmark : .none
            case 3:
                // Card memo (for cardOnFile and split)
                let container = UIView()
                container.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(cardMemo)
                cell.contentView.addSubview(container)
                container.frame = cell.contentView.bounds
                cardMemo.frame = cell.contentView.bounds.insetBy(dx: 16, dy: 6)
                cardMemo.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                return cell
            case 4:
                // Split amounts
                let row = UIStackView(arrangedSubviews: [cashField, cardField])
                row.axis = .horizontal
                row.spacing = 8
                row.distribution = .fillEqually
                row.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(row)
                row.frame = cell.contentView.bounds.insetBy(dx: 16, dy: 6)
                row.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                return cell
            default: break
            }
        }
        cell.contentConfiguration = config
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1, indexPath.row < 3 else { return }
        switch indexPath.row {
        case 0: mode = .cash
        case 1: mode = .cardOnFile
        case 2: mode = .split
        default: break
        }
        tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
    }
}
