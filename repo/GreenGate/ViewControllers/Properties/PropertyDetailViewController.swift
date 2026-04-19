import UIKit
import UniformTypeIdentifiers

/// Full details + workflow actions (submit/approve/reject/lock/unlock/unpublish
/// per role) + change-history entry point.
final class PropertyDetailViewController: UIViewController {

    private let listing: PropertyListing
    private let service: PropertyService
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(listing: PropertyListing, service: PropertyService = .shared) {
        self.listing = listing
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = listing.title
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        setupNavigationBar()
        setupTableView()
    }

    private func setupNavigationBar() {
        var items: [UIBarButtonItem] = []
        if canEdit {
            items.append(UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(editTapped)))
        }
        items.append(UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"),
                                     style: .plain, target: self, action: #selector(actionsTapped)))
        if canViewHistory {
            items.append(UIBarButtonItem(image: UIImage(systemName: "clock.arrow.circlepath"),
                                         style: .plain, target: self, action: #selector(historyTapped)))
        }
        navigationItem.rightBarButtonItems = items
    }

    private var canEdit: Bool {
        listing.status != PropertyStatus.locked.rawValue
    }

    private var canViewHistory: Bool {
        guard let role = AuthService.shared.currentUser?.role else { return false }
        return role == Role.admin.rawValue || role == Role.reviewer.rawValue
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    @objc private func editTapped() {
        let vc = PropertyFormViewController(listing: listing)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func historyTapped() {
        navigationController?.pushViewController(ChangeHistoryViewController(listing: listing),
                                                  animated: true)
    }

    @objc private func actionsTapped() {
        let status = PropertyStatus(rawValue: listing.status) ?? .draft
        guard let user = AuthService.shared.currentUser else {
            let alert = UIAlertController(title: "Error",
                                          message: "You must be logged in to perform workflow actions.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let isReviewer = user.role == Role.reviewer.rawValue || user.role == Role.admin.rawValue
        let isAdmin    = user.role == Role.admin.rawValue

        let alert = UIAlertController(title: "Workflow", message: nil, preferredStyle: .actionSheet)
        switch status {
        case .draft:
            alert.addAction(UIAlertAction(title: "Submit for Review", style: .default) { _ in
                self.run { try self.service.submitForReview(listingID: self.listing.id, actor: user) }
            })
        case .inReview where isReviewer:
            alert.addAction(UIAlertAction(title: "Approve", style: .default) { _ in
                self.run { try self.service.approve(listingID: self.listing.id, reviewer: user) }
            })
            alert.addAction(UIAlertAction(title: "Reject", style: .destructive) { _ in
                self.promptReject(reviewer: user)
            })
        case .published:
            if isAdmin {
                alert.addAction(UIAlertAction(title: "Lock", style: .destructive) { _ in
                    AuthService.shared.biometricAuth(reason: "Confirm identity to lock this listing") { result in
                        DispatchQueue.main.async {
                            guard case .success = result else { return }
                            self.run { try self.service.lock(listingID: self.listing.id, admin: user) }
                        }
                    }
                })
            }
            alert.addAction(UIAlertAction(title: "Unpublish", style: .default) { _ in
                self.run { try self.service.unpublish(listingID: self.listing.id, actor: user) }
            })
        case .locked where isAdmin:
            alert.addAction(UIAlertAction(title: "Unlock", style: .default) { _ in
                AuthService.shared.biometricAuth(reason: "Confirm identity to unlock this listing") { result in
                    DispatchQueue.main.async {
                        guard case .success = result else { return }
                        self.run { try self.service.unlock(listingID: self.listing.id, admin: user) }
                    }
                }
            })
        default: break
        }
        let isContentManagerOrAdmin = user.role == Role.contentManager.rawValue
                                   || user.role == Role.admin.rawValue
        if status != .locked && isContentManagerOrAdmin {
            alert.addAction(UIAlertAction(title: "Attach Floor Plan", style: .default) { _ in
                self.presentFloorPlanPicker()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func presentFloorPlanPicker() {
        let types: [UTType] = [.image, .movie, .pdf]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func promptReject(reviewer: User) {
        let alert = UIAlertController(title: "Reject", message: "Notes:", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Required" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reject", style: .destructive) { _ in
            let notes = alert.textFields?.first?.text ?? ""
            self.run { try self.service.reject(listingID: self.listing.id,
                                                reviewer: reviewer, notes: notes) }
        })
        present(alert, animated: true)
    }

    private func run(_ block: () throws -> Void) {
        do {
            try block()
            tableView.reloadData()
            setupNavigationBar()
        } catch {
            let alert = UIAlertController(title: "Error", message: error.localizedDescription,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

extension PropertyDetailViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let ext = url.pathExtension.lowercased()
        let mimeType: AttachmentMimeType
        switch ext {
        case "jpg", "jpeg": mimeType = .jpeg
        case "png":         mimeType = .png
        case "heic":        mimeType = .heic
        case "mov":         mimeType = .mov
        case "pdf":         mimeType = .pdf
        default:            mimeType = .mp4
        }

        guard let user = AuthService.shared.currentUser else { return }
        let attachmentService = AttachmentService(
            context: CoreDataStack.shared.newBackgroundContext()
        )
        let listingID = listing.id

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let input = AttachmentService.UploadInput(
                    sourceURL: url,
                    declaredMime: mimeType,
                    parentType: .property,
                    parentID: listingID,
                    licensing: nil,
                    copyright: nil
                )
                let attachment = try attachmentService.upload(input, uploadedBy: user)
                try self.service.registerFloorPlan(listingID: listingID,
                                                   attachmentID: attachment.id,
                                                   actor: user)
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Error",
                                                  message: error.localizedDescription,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
}

extension PropertyDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Details", "Financials", "Status"][section]
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        [5, 3, 2][section]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        switch indexPath.section {
        case 0:
            let pairs: [(String, String)] = [
                ("Title",      listing.title),
                ("Address",    "\(listing.addressLine1)\(listing.addressLine2.map { ", \($0)" } ?? "")"),
                ("City",       "\(listing.city), \(listing.state) \(listing.zipCode)"),
                ("Sq Footage", "\(listing.squareFootage) sq ft"),
                ("Amenities",  listing.amenitiesArray.isEmpty ? "—" : listing.amenitiesArray.joined(separator: ", ")),
            ]
            config.text = pairs[indexPath.row].0
            config.secondaryText = pairs[indexPath.row].1
        case 1:
            let pairs: [(String, String)] = [
                ("Rent",       CurrencyFormatter.string(fromCents: listing.rentCents) + "/mo"),
                ("Deposit",    CurrencyFormatter.string(fromCents: listing.depositCents)),
                ("Lease Term", "\(listing.leaseTermMonths) months"),
            ]
            config.text = pairs[indexPath.row].0
            config.secondaryText = pairs[indexPath.row].1
        case 2:
            let pairs: [(String, String)] = [
                ("Status",         PropertyStatus(rawValue: listing.status)?.displayName ?? listing.status),
                ("Available From", DateFormatters.shortDate.string(from: listing.availableFrom)),
            ]
            config.text = pairs[indexPath.row].0
            config.secondaryText = pairs[indexPath.row].1
        default: break
        }
        cell.contentConfiguration = config
        return cell
    }
}
