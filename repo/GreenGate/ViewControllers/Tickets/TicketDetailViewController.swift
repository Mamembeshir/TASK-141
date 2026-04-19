import UIKit
import CoreImage

/// Ticket details with QR image, status, and check-in log timeline.
final class TicketDetailViewController: UIViewController {

    private let ticket: ETicket
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let qrImageView = UIImageView()

    init(ticket: ETicket) {
        self.ticket = ticket
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Ticket \(ticket.ticketNumber)"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        setupLayout()
        loadQRCode()
        if AuthService.shared.currentUser?.role == Role.admin.rawValue,
           ticket.status == TicketStatus.valid.rawValue {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "Void", style: .plain, target: self, action: #selector(voidTapped)
            )
            navigationItem.rightBarButtonItem?.tintColor = UIColor(named: "Danger") ?? .systemRed
        }
    }

    @objc private func voidTapped() {
        guard let actor = AuthService.shared.currentUser else { return }
        let confirm = UIAlertController(
            title: "Void Ticket",
            message: "This will permanently invalidate ticket \(ticket.ticketNumber). Proceed?",
            preferredStyle: .alert
        )
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirm.addAction(UIAlertAction(title: "Void", style: .destructive) { [weak self] _ in
            guard let self else { return }
            AuthService.shared.biometricAuth(reason: "Confirm identity to void ticket") { result in
                DispatchQueue.main.async {
                    guard case .success = result else { return }
                    do {
                        try TicketService.shared.voidTicket(
                            ticketID: self.ticket.id,
                            actorID: actor.id,
                            actor: actor
                        )
                        self.navigationItem.rightBarButtonItem = nil
                        self.tableView.reloadData()
                    } catch {
                        let alert = UIAlertController(title: "Error",
                                                      message: error.localizedDescription,
                                                      preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            }
        })
        present(confirm, animated: true)
    }

    private func setupLayout() {
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.layer.cornerRadius = 8
        qrImageView.clipsToBounds = true
        qrImageView.backgroundColor = .white
        qrImageView.translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        view.addSubview(qrImageView)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            qrImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            qrImageView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 200),
            qrImageView.heightAnchor.constraint(equalToConstant: 200),

            tableView.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func loadQRCode() {
        qrImageView.image = BarcodeGenerator.qrCode(from: ticket.qrPayload)
        qrImageView.accessibilityLabel = "Ticket QR Code"
    }
}

extension TicketDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Ticket" : "Check-In Log"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 5 : max(ticket.checkInLogsArray.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let pairs: [(String, String)] = [
                ("Ticket #",   ticket.ticketNumber),
                ("Holder",     ticket.holderName ?? "—"),
                ("Status",     TicketStatus(rawValue: ticket.status)?.displayName ?? ticket.status),
                ("Valid From", DateFormatters.shortDateTime.string(from: ticket.validFrom)),
                ("Valid To",   DateFormatters.shortDateTime.string(from: ticket.validTo)),
            ]
            config.text = pairs[indexPath.row].0
            config.secondaryText = pairs[indexPath.row].1
        } else {
            let logs = ticket.checkInLogsArray
            if logs.isEmpty {
                config.text = "No check-ins yet"
                config.textProperties.color = UIColor(named: "TextTertiary") ?? .tertiaryLabel
            } else {
                let log = logs[indexPath.row]
                config.text = log.result
                config.secondaryText = "\(DateFormatters.shortDateTime.string(from: log.scannedAt)) · \(log.scannedBy?.username ?? "—")"
            }
        }
        cell.contentConfiguration = config
        return cell
    }
}
