import UIKit

/// Event header + ticket roster + actions: publish (DRAFT→ON_SALE) and
/// generate ticket (creates a signed ETicket, navigates to its QR view).
/// When initialised with `event: nil` the controller shows a creation form.
final class EventDetailViewController: UIViewController {

    private var event: TicketEvent?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let service: TicketService

    // MARK: - Creation form views (used only when event == nil)

    private let formScrollView = UIScrollView()
    private let formStack      = UIStackView()
    private let nameField      = UITextField()
    private let venueField     = UITextField()
    private let capacityField  = UITextField()
    private let eventDatePicker = UIDatePicker()
    private let doorOpenPicker  = UIDatePicker()
    private let doorClosePicker = UIDatePicker()

    init(event: TicketEvent?, service: TicketService = .shared) {
        self.event = event
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = event?.name ?? "New Event"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        if event == nil {
            setupCreationForm()
        } else {
            setupTableView()
        }
        rebuildBarItems()
    }

    // MARK: - Bar items

    private func rebuildBarItems() {
        if event == nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "Save", style: .done, target: self, action: #selector(saveTapped)
            )
            return
        }
        var items: [UIBarButtonItem] = []
        let scan = UIBarButtonItem(image: UIImage(systemName: "qrcode.viewfinder"),
                                   style: .plain, target: self, action: #selector(scanTapped))
        items.append(scan)
        if event?.status == EventStatus.draft.rawValue {
            items.append(UIBarButtonItem(title: "Publish", style: .done,
                                          target: self, action: #selector(publishTapped)))
        } else if event?.status == EventStatus.onSale.rawValue {
            items.append(UIBarButtonItem(title: "Issue", style: .plain,
                                          target: self, action: #selector(generateTapped)))
        }
        navigationItem.rightBarButtonItems = items
    }

    // MARK: - Creation form

    private func setupCreationForm() {
        formScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(formScrollView)
        NSLayoutConstraint.activate([
            formScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            formScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            formScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            formScrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        formStack.axis = .vertical
        formStack.spacing = 0
        formStack.translatesAutoresizingMaskIntoConstraints = false
        formScrollView.addSubview(formStack)
        NSLayoutConstraint.activate([
            formStack.topAnchor.constraint(equalTo: formScrollView.topAnchor, constant: 20),
            formStack.leadingAnchor.constraint(equalTo: formScrollView.leadingAnchor, constant: 20),
            formStack.trailingAnchor.constraint(equalTo: formScrollView.trailingAnchor, constant: -20),
            formStack.bottomAnchor.constraint(equalTo: formScrollView.bottomAnchor, constant: -20),
            formStack.widthAnchor.constraint(equalTo: formScrollView.widthAnchor, constant: -40),
        ])

        let card = UIView()
        card.backgroundColor = UIColor(named: "SurfaceCard") ?? .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        formStack.addArrangedSubview(card)

        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.spacing = 0
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        configureTextField(nameField, placeholder: "Required")
        configureTextField(venueField, placeholder: "Optional")
        configureTextField(capacityField, placeholder: "e.g. 500")
        capacityField.keyboardType = .numberPad

        let now = Date()
        for picker in [eventDatePicker, doorOpenPicker, doorClosePicker] {
            picker.preferredDatePickerStyle = .compact
            picker.datePickerMode = .dateAndTime
            picker.minuteInterval = 15
            picker.date = now
        }
        doorOpenPicker.date = now
        doorClosePicker.date = now.addingTimeInterval(3 * 3600)

        let rows: [(String, UIView)] = [
            ("Name",       nameField),
            ("Venue",      venueField),
            ("Capacity",   capacityField),
            ("Event Date", eventDatePicker),
            ("Door Open",  doorOpenPicker),
            ("Door Close", doorClosePicker),
        ]

        for (index, (label, field)) in rows.enumerated() {
            let row = makeFormRow(label: label, control: field)
            cardStack.addArrangedSubview(row)
            if index < rows.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                cardStack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            }
        }
    }

    private func configureTextField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .none
        field.returnKeyType = .next
        field.clearButtonMode = .whileEditing
    }

    private func makeFormRow(label: String, control: UIView) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        row.isLayoutMarginsRelativeArrangement = true

        let lbl = UILabel()
        lbl.text = label
        lbl.font = UIFont.preferredFont(forTextStyle: .body)
        lbl.setContentHuggingPriority(.required, for: .horizontal)
        lbl.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addArrangedSubview(lbl)
        row.addArrangedSubview(control)
        return row
    }

    // MARK: - Save (creation)

    @objc private func saveTapped() {
        let name = nameField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else {
            showError("Event name is required.")
            return
        }
        let capacityText = capacityField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let capacity = Int32(capacityText), capacity > 0 else {
            showError("Capacity must be a positive whole number.")
            return
        }
        let venue = venueField.text?.trimmingCharacters(in: .whitespaces)
        let eventDate = eventDatePicker.date
        let doorOpen  = doorOpenPicker.date
        let doorClose = doorClosePicker.date
        guard doorClose > doorOpen else {
            showError("Door close must be after door open.")
            return
        }
        guard let currentUser = AuthService.shared.currentUser else {
            showError("You must be signed in to create an event.")
            return
        }
        do {
            let created = try service.createEvent(
                name: name,
                venue: venue?.isEmpty == false ? venue : nil,
                date: eventDate,
                doorOpen: doorOpen,
                doorClose: doorClose,
                capacity: capacity,
                actor: currentUser
            )
            self.event = created
            title = created.name
            formScrollView.removeFromSuperview()
            setupTableView()
            rebuildBarItems()
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - Detail table

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    @objc private func scanTapped() {
        navigationController?.pushViewController(TicketScannerViewController(), animated: true)
    }

    @objc private func publishTapped() {
        guard let event = event else { return }
        guard let actor = AuthService.shared.currentUser else {
            showError("You must be logged in to publish an event.")
            return
        }
        do {
            try service.publishEvent(eventID: event.id, actor: actor)
            tableView.reloadData()
            rebuildBarItems()
        } catch { showError(error.localizedDescription) }
    }

    @objc private func generateTapped() {
        guard let event = event else { return }
        guard let actor = AuthService.shared.currentUser else {
            showError("You must be signed in to issue a ticket.")
            return
        }
        do {
            let ticket = try service.generateTicket(eventID: event.id,
                                                    holderName: nil, actor: actor)
            tableView.reloadData()
            rebuildBarItems()
            let detail = TicketDetailViewController(ticket: ticket)
            navigationController?.pushViewController(detail, animated: true)
        } catch { showError(error.localizedDescription) }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension EventDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Event Details"
        case 1: return "Capacity"
        case 2: return "Tickets"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 4
        case 1: return 3
        case 2: return max(event?.ticketsArray.count ?? 0, 1)
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        switch indexPath.section {
        case 0:
            let pairs: [(String, String)] = [
                ("Name",  event?.name ?? "—"),
                ("Venue", event?.venue ?? "—"),
                ("Date",  event.flatMap { DateFormatters.shortDate.string(from: $0.eventDate) } ?? "—"),
                ("Status", EventStatus(rawValue: event?.status ?? "")?.displayName ?? (event?.status ?? "—")),
            ]
            config.text = pairs[indexPath.row].0
            config.secondaryText = pairs[indexPath.row].1
        case 1:
            let pairs: [(String, String)] = [
                ("Capacity",   "\(event?.totalCapacity ?? 0)"),
                ("Sold",       "\(event?.soldCount ?? 0)"),
                ("Checked In", "\(event?.checkedInCount ?? 0)"),
            ]
            config.text = pairs[indexPath.row].0
            config.secondaryText = pairs[indexPath.row].1
        case 2:
            if let tickets = event?.ticketsArray, !tickets.isEmpty {
                let t = tickets[indexPath.row]
                config.text = t.ticketNumber
                config.secondaryText = "\(t.holderName ?? "—") · \(TicketStatus(rawValue: t.status)?.displayName ?? t.status)"
                cell.accessoryType = .disclosureIndicator
            } else {
                config.text = "No tickets issued"
                config.textProperties.color = UIColor(named: "TextTertiary") ?? .tertiaryLabel
            }
        default: break
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 2,
              let tickets = event?.ticketsArray, !tickets.isEmpty else { return }
        let detail = TicketDetailViewController(ticket: tickets[indexPath.row])
        navigationController?.pushViewController(detail, animated: true)
    }
}
