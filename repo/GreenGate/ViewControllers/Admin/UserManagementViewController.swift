import UIKit
import CoreData

/// Admin screen for listing and managing users. The caller is responsible
/// for only pushing/showing this VC when the current user has role `.admin`.
final class UserManagementViewController: UIViewController {

    private let tableView  = UITableView(frame: .zero, style: .insetGrouped)
    private var fetchedRC: NSFetchedResultsController<User>?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard AuthService.shared.currentUser?.role == Role.admin.rawValue else {
            navigationController?.popViewController(animated: false)
            return
        }
        title = "User Management"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self, action: #selector(addTapped)
        )
        setupTableView()
        setupFRC()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UserCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func setupFRC() {
        let fetch = NSFetchRequest<User>(entityName: "User")
        fetch.sortDescriptors = [NSSortDescriptor(key: "username", ascending: true)]
        fetchedRC = NSFetchedResultsController(
            fetchRequest: fetch,
            managedObjectContext: CoreDataStack.shared.viewContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        fetchedRC?.delegate = self
        try? fetchedRC?.performFetch()
    }

    // MARK: - Add user

    @objc private func addTapped() {
        let alert = UIAlertController(title: "New User",
                                      message: "Username, password, and role.",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Username"
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.accessibilityIdentifier = "newUser.username"
        }
        alert.addTextField { tf in
            tf.placeholder = "Password (min 8, ≥1 number)"
            tf.isSecureTextEntry = true
            tf.accessibilityIdentifier = "newUser.password"
        }
        alert.addTextField { tf in
            tf.placeholder = "Role (ADMIN / CASHIER / GATE_ATTENDANT / CONTENT_MANAGER / REVIEWER)"
            tf.autocapitalizationType = .allCharacters
            tf.autocorrectionType = .no
            tf.accessibilityIdentifier = "newUser.role"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            guard let self, let alert else { return }
            let username = alert.textFields?[0].text ?? ""
            let password = alert.textFields?[1].text ?? ""
            let roleStr  = alert.textFields?[2].text ?? ""
            guard let role = Role(rawValue: roleStr.uppercased()) else {
                self.presentError("Unknown role. Use one of: ADMIN, CASHIER, GATE_ATTENDANT, CONTENT_MANAGER, REVIEWER.")
                return
            }
            do {
                _ = try AuthService.shared.register(
                    username: username,
                    password: password,
                    role: role,
                    actorID: AuthService.shared.currentUser?.id,
                    context: CoreDataStack.shared.viewContext
                )
            } catch let e as AuthError {
                self.presentError(e.errorDescription ?? "Could not create user.")
            } catch {
                self.presentError(error.localizedDescription)
            }
        })
        present(alert, animated: true)
    }

    private func presentError(_ message: String) {
        let a = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    // MARK: - Lock / Unlock

    private func toggleLock(_ user: User) {
        let current = UserStatus(rawValue: user.status) ?? .active
        let newStatus: UserStatus = (current == .active) ? .locked : .active
        let verb = newStatus == .locked ? "lock" : "unlock"
        AuthService.shared.biometricAuth(reason: "Confirm identity to \(verb) \(user.username)") { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success(let authUser) = result else { return }
                do {
                    try AuthService.shared.setStatus(
                        newStatus,
                        for: user,
                        actorID: authUser.id,
                        context: CoreDataStack.shared.viewContext
                    )
                } catch {
                    self.presentError(error.localizedDescription)
                }
            }
        }
    }
}

extension UserManagementViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fetchedRC?.fetchedObjects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell", for: indexPath)
        guard let user = fetchedRC?.object(at: indexPath) else { return cell }
        var config = cell.defaultContentConfiguration()
        config.text = user.username
        let role = Role(rawValue: user.role)?.displayName ?? user.role
        let status = UserStatus(rawValue: user.status)?.rawValue.capitalized ?? user.status
        config.secondaryText = "\(role) · \(status)"
        config.textProperties.adjustsFontForContentSizeCategory = true
        config.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }
}

extension UserManagementViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let user = fetchedRC?.object(at: indexPath) else { return nil }
        let isLocked = (user.status == UserStatus.locked.rawValue)
        let title = isLocked ? "Unlock" : "Lock"
        let action = UIContextualAction(style: isLocked ? .normal : .destructive,
                                        title: title) { [weak self] _, _, done in
            self?.toggleLock(user)
            done(true)
        }
        action.backgroundColor = isLocked
            ? (UIColor(named: "Success") ?? .systemGreen)
            : (UIColor(named: "Warning") ?? .systemOrange)
        return UISwipeActionsConfiguration(actions: [action])
    }
}

extension UserManagementViewController: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.reloadData()
    }
}
