import UIKit
import CoreData

/// Lists all LearningContent articles. Content Managers can create new ones;
/// Admins and Reviewers can publish; Admins can archive.
final class LearningContentListViewController: UIViewController {

    private let tableView  = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyState = EmptyStateView()
    private let service: LearningContentService
    private var items: [LearningContent] = []

    init(service: LearningContentService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Learning"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .always
        setupNavigationBar()
        setupTableView()
        setupEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func setupNavigationBar() {
        let role = AuthService.shared.currentUser?.role
        let canCreate = role == Role.contentManager.rawValue || role == Role.admin.rawValue
        if canCreate {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .add, target: self, action: #selector(addTapped)
            )
        }
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
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
        emptyState.configure(
            systemImage: "book.fill",
            title: "No Learning Content",
            subtitle: "Create articles to share knowledge with your team.",
            ctaTitle: "New Article"
        )
        emptyState.onCTATapped = { [weak self] in self?.addTapped() }
    }

    private func reload() {
        items = (try? service.fetchAll()) ?? []
        let empty = items.isEmpty
        tableView.isHidden = empty
        emptyState.isHidden = !empty
        tableView.reloadData()
    }

    @objc private func addTapped() {
        let vc = LearningContentDetailViewController(content: nil, service: service)
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension LearningContentListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let item = items[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text          = item.title
        config.secondaryText = "\(LearningContentStatus(rawValue: item.status)?.displayName ?? item.status)"
                              + (item.category.map { " · \($0)" } ?? "")
        cell.contentConfiguration  = config
        cell.accessoryType         = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let vc = LearningContentDetailViewController(content: items[indexPath.row], service: service)
        navigationController?.pushViewController(vc, animated: true)
    }
}
