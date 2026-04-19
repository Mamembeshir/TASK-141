import UIKit
import CoreData

/// Lists all SPUs with their status badge and SKU count. Backed by an
/// NSFetchedResultsController so the list auto-refreshes on save.
final class ProductListViewController: UIViewController {

    private let tableView  = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyState = EmptyStateView()
    private(set) var fetchedRC: NSFetchedResultsController<ProductSPU>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Products"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        setupNavigationBar()
        setupTableView()
        setupEmptyState()
        setupFRC()
    }

    private func setupNavigationBar() {
        navigationItem.largeTitleDisplayMode = .always
        let add = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        navigationItem.rightBarButtonItem = add
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(ProductListCell.self, forCellReuseIdentifier: "ProductCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refresh
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
            systemImage: "leaf.fill",
            title: "No Products",
            subtitle: "Add your first product to get started.",
            ctaTitle: "Add Product"
        )
        emptyState.onCTATapped = { [weak self] in self?.addTapped() }
    }

    private func setupFRC() {
        let fetch = NSFetchRequest<ProductSPU>(entityName: "ProductSPU")
        fetch.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        fetchedRC = NSFetchedResultsController(
            fetchRequest: fetch,
            managedObjectContext: CoreDataStack.shared.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        fetchedRC?.delegate = self
        try? fetchedRC?.performFetch()
        updateEmptyState()
    }

    private func updateEmptyState() {
        let empty = (fetchedRC?.fetchedObjects?.isEmpty) ?? true
        tableView.isHidden = empty
        emptyState.isHidden = !empty
    }

    @objc private func addTapped() {
        let vc = ProductFormViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func refreshData() {
        try? fetchedRC?.performFetch()
        tableView.reloadData()
        tableView.refreshControl?.endRefreshing()
    }
}

extension ProductListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fetchedRC?.fetchedObjects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ProductCell", for: indexPath) as! ProductListCell
        if let spu = fetchedRC?.object(at: indexPath) {
            cell.configure(with: spu)
        }
        return cell
    }
}

extension ProductListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let spu = fetchedRC?.object(at: indexPath) else { return }
        let detail = ProductDetailViewController(spu: spu)
        navigationController?.pushViewController(detail, animated: true)
    }
}

extension ProductListViewController: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.reloadData()
        updateEmptyState()
    }
}

// MARK: - Cell

final class ProductListCell: UITableViewCell {

    let thumbnail  = UIImageView()
    let nameLabel  = UILabel()
    let skuLabel   = UILabel()
    let badge      = StatusBadgeView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        accessoryType = .disclosureIndicator

        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.image = UIImage(systemName: "leaf.fill")
        thumbnail.tintColor = UIColor(named: "GreenPrimary")
        thumbnail.contentMode = .scaleAspectFit
        thumbnail.setContentHuggingPriority(.required, for: .horizontal)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true

        skuLabel.translatesAutoresizingMaskIntoConstraints = false
        skuLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        skuLabel.adjustsFontForContentSizeCategory = true
        skuLabel.textColor = UIColor(named: "TextSecondary")

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.setContentHuggingPriority(.required, for: .horizontal)

        contentView.addSubview(thumbnail)
        contentView.addSubview(nameLabel)
        contentView.addSubview(skuLabel)
        contentView.addSubview(badge)

        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            thumbnail.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 32),
            thumbnail.heightAnchor.constraint(equalToConstant: 32),

            nameLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),

            skuLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            skuLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            skuLabel.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            skuLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),

            badge.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            badge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    func configure(with spu: ProductSPU) {
        nameLabel.text = spu.name
        let count = spu.skusArray.count
        skuLabel.text = "\(count) SKU\(count == 1 ? "" : "s") · \(spu.category ?? "Uncategorized")"
        let status = ProductListingStatus(rawValue: spu.listingStatus)?.displayName ?? spu.listingStatus
        badge.configure(status: status)
    }
}
