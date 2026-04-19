import UIKit

/// Per-field change-history timeline. Each row: fieldName · old → new, with
/// actor and time. Grouped by save timestamp (rows within the same second
/// land in the same section).
final class ChangeHistoryViewController: UIViewController {

    private let listing: PropertyListing
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    /// Groups of (timestamp string, [changes]).
    private var groups: [(label: String, entries: [PropertyChangeHistory])] = []

    init(listing: PropertyListing) {
        self.listing = listing
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Change History"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        setupLayout()
        reload()
    }

    private func setupLayout() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func reload() {
        let entries = listing.changeHistoryArray.sorted { $0.changedAt > $1.changedAt }
        var buckets: [(key: TimeInterval, label: String, list: [PropertyChangeHistory])] = []
        for e in entries {
            // Bucket by second — a single save will have matching timestamps.
            let key = floor(e.changedAt.timeIntervalSince1970)
            if let idx = buckets.firstIndex(where: { $0.key == key }) {
                buckets[idx].list.append(e)
            } else {
                buckets.append((
                    key: key,
                    label: DateFormatters.shortDateTime.string(from: e.changedAt),
                    list: [e]
                ))
            }
        }
        groups = buckets.map { ($0.label, $0.list) }
        tableView.reloadData()
    }
}

extension ChangeHistoryViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        groups.isEmpty ? 1 : groups.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        groups.isEmpty ? nil : groups[section].label
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups.isEmpty ? 1 : groups[section].entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if groups.isEmpty {
            config.text = "No changes recorded yet."
            config.textProperties.color = UIColor(named: "TextTertiary") ?? .tertiaryLabel
        } else {
            let entry = groups[indexPath.section].entries[indexPath.row]
            config.text = "\(entry.fieldName): \(entry.oldValue ?? "—") → \(entry.newValue ?? "—")"
            config.secondaryText = entry.changedBy?.username ?? "system"
        }
        cell.contentConfiguration = config
        return cell
    }
}
