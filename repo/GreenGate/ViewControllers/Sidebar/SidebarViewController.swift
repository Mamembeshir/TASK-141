import UIKit

/// iPad sidebar — lists app sections permitted for the authenticated user's role.
final class SidebarViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private struct SidebarItem {
        let title: String
        let icon: String
        let makeVC: () -> UIViewController
    }

    private let role: Role?
    private lazy var items: [SidebarItem] = buildItems(for: role)

    init(role: Role?) {
        self.role = role
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.role = nil
        super.init(coder: coder)
    }

    private func buildItems(for role: Role?) -> [SidebarItem] {
        let allowed = role?.allowedModules ?? []
        var result: [SidebarItem] = []
        if allowed.contains(.dashboard) {
            result.append(SidebarItem(title: "Dashboard",     icon: "house.fill")            { DashboardViewController() })
        }
        if allowed.contains(.products) {
            result.append(SidebarItem(title: "Products",      icon: "leaf.fill")             { ProductListViewController() })
        }
        if allowed.contains(.pos) {
            result.append(SidebarItem(title: "POS",           icon: "cart.fill")             { POSViewController() })
        }
        if allowed.contains(.tickets) {
            result.append(SidebarItem(title: "Events",        icon: "ticket.fill")           { EventListViewController() })
        }
        if allowed.contains(.properties) {
            result.append(SidebarItem(title: "Properties",    icon: "building.2.fill")       { PropertyListViewController() })
        }
        if allowed.contains(.learningContent) {
            result.append(SidebarItem(title: "Learning",      icon: "book.fill")             { LearningContentListViewController() })
        }
        if allowed.contains(.userManagement) {
            result.append(SidebarItem(title: "Users",         icon: "person.2.fill")         { UserManagementViewController() })
        }
        if allowed.contains(.auditLog) {
            result.append(SidebarItem(title: "Audit Log",     icon: "doc.text.fill")         { AuditLogViewController() })
        }
        if allowed.contains(.importExport) {
            result.append(SidebarItem(title: "Import/Export", icon: "arrow.up.arrow.down")   { ImportExportViewController() })
        }
        return result
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "GreenGate"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .always
        setupTableView()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SidebarCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        // Select Dashboard by default
        DispatchQueue.main.async {
            self.tableView.selectRow(at: IndexPath(row: 0, section: 0),
                                     animated: false, scrollPosition: .none)
        }
    }
}

extension SidebarViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SidebarCell", for: indexPath)
        let item = items[indexPath.row]
        var config = UIListContentConfiguration.sidebarCell()
        config.text  = item.title
        config.image = UIImage(systemName: item.icon)
        cell.contentConfiguration = config
        cell.accessibilityLabel = item.title
        return cell
    }
}

extension SidebarViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let split = splitViewController else { return }
        let item = items[indexPath.row]
        let detail = UINavigationController(rootViewController: item.makeVC())

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        detail.navigationBar.standardAppearance  = appearance
        detail.navigationBar.scrollEdgeAppearance = appearance
        detail.navigationBar.prefersLargeTitles   = true

        split.setViewController(detail, for: .secondary)
    }
}
