import UIKit

/// View/edit a LearningContent article. When `content == nil` it enters creation
/// mode with a form; when content is supplied it shows the detail with workflow actions.
final class LearningContentDetailViewController: UIViewController {

    private var content: LearningContent?
    private let service: LearningContentService
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    // Creation-form views
    private let formScrollView  = UIScrollView()
    private let titleField      = UITextField()
    private let categoryField   = UITextField()
    private let bodyView        = UITextView()

    init(content: LearningContent?, service: LearningContentService = .shared) {
        self.content = content
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = content?.title ?? "New Article"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        if content == nil {
            setupCreationForm()
        } else {
            setupDetailTable()
        }
        rebuildBarItems()
    }

    // MARK: - Bar items

    private func rebuildBarItems() {
        if content == nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "Save", style: .done, target: self, action: #selector(saveTapped)
            )
            return
        }
        guard let content = content else { return }
        let user   = AuthService.shared.currentUser
        let role   = user?.role
        let status = LearningContentStatus(rawValue: content.status) ?? .draft
        var items: [UIBarButtonItem] = []

        let canEdit    = role == Role.contentManager.rawValue || role == Role.admin.rawValue
        let canPublish = role == Role.admin.rawValue || role == Role.reviewer.rawValue
        let canArchive = role == Role.admin.rawValue

        if canEdit && status != .archived {
            items.append(UIBarButtonItem(barButtonSystemItem: .edit,
                                         target: self, action: #selector(editTapped)))
        }
        if canPublish && status == .draft {
            items.append(UIBarButtonItem(title: "Publish", style: .done,
                                          target: self, action: #selector(publishTapped)))
        }
        if canArchive && status == .published {
            items.append(UIBarButtonItem(title: "Archive", style: .plain,
                                          target: self, action: #selector(archiveTapped)))
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

        let card = UIView()
        card.backgroundColor = UIColor(named: "SurfaceCard") ?? .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        formScrollView.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: formScrollView.topAnchor, constant: 20),
            card.leadingAnchor.constraint(equalTo: formScrollView.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: formScrollView.trailingAnchor, constant: -20),
            card.bottomAnchor.constraint(equalTo: formScrollView.bottomAnchor, constant: -20),
            card.widthAnchor.constraint(equalTo: formScrollView.widthAnchor, constant: -40),
        ])

        configure(titleField,    placeholder: "Required")
        configure(categoryField, placeholder: "Optional")

        bodyView.font = UIFont.preferredFont(forTextStyle: .body)
        bodyView.backgroundColor = .clear
        bodyView.isScrollEnabled = false
        bodyView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        bodyView.layer.borderColor = UIColor.separator.cgColor
        bodyView.layer.borderWidth = 0.5
        bodyView.layer.cornerRadius = 8
        bodyView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])

        let bodyContainer = UIView()
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(bodyView)
        NSLayoutConstraint.activate([
            bodyView.topAnchor.constraint(equalTo: bodyContainer.topAnchor, constant: 12),
            bodyView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: 16),
            bodyView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -16),
            bodyView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -12),
            bodyView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])

        let rows: [(String, UIView)] = [
            ("Title",    titleField),
            ("Category", categoryField),
        ]
        for (index, (label, field)) in rows.enumerated() {
            stack.addArrangedSubview(makeFormRow(label: label, control: field))
            if index < rows.count - 1 {
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            }
        }
        let sep2 = UIView()
        sep2.backgroundColor = .separator
        sep2.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep2)
        sep2.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(bodyContainer)
        // constrain card bottom to stack bottom
        card.bottomAnchor.constraint(equalTo: stack.bottomAnchor).isActive = true
    }

    private func configure(_ field: UITextField, placeholder: String) {
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
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(control)
        return row
    }

    @objc private func saveTapped() {
        let titleText = titleField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !titleText.isEmpty else { showError("Title is required."); return }
        let bodyText = bodyView.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !bodyText.isEmpty else { showError("Body is required."); return }
        let cat = categoryField.text?.trimmingCharacters(in: .whitespaces)
        guard let actor = AuthService.shared.currentUser else {
            showError("You must be logged in to create content.")
            return
        }
        do {
            let created = try service.create(title: titleText, body: bodyText,
                                              category: cat?.isEmpty == false ? cat : nil,
                                              actor: actor)
            self.content = created
            title = created.title
            formScrollView.removeFromSuperview()
            setupDetailTable()
            rebuildBarItems()
        } catch { showError(error.localizedDescription) }
    }

    // MARK: - Detail table

    private func setupDetailTable() {
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
        guard let content = content else { return }
        let vc = LearningContentEditViewController(content: content, service: service) { [weak self] in
            self?.tableView.reloadData()
            self?.rebuildBarItems()
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func publishTapped() {
        guard let content = content else { return }
        guard let actor = AuthService.shared.currentUser else {
            showError("You must be logged in to publish content.")
            return
        }
        do {
            try service.publish(contentID: content.id, actor: actor)
            tableView.reloadData()
            rebuildBarItems()
        } catch { showError(error.localizedDescription) }
    }

    @objc private func archiveTapped() {
        guard let content = content else { return }
        guard let actor = AuthService.shared.currentUser else {
            showError("You must be logged in to archive content.")
            return
        }
        do {
            try service.archive(contentID: content.id, actor: actor)
            tableView.reloadData()
            rebuildBarItems()
        } catch { showError(error.localizedDescription) }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension LearningContentDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Details" : "Content"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 3 : 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let pairs: [(String, String)] = [
                ("Title",    content?.title ?? "—"),
                ("Category", content?.category ?? "—"),
                ("Status",   LearningContentStatus(rawValue: content?.status ?? "")?.displayName
                             ?? (content?.status ?? "—")),
            ]
            config.text          = pairs[indexPath.row].0
            config.secondaryText = pairs[indexPath.row].1
        } else {
            config.text = content?.body ?? "—"
            config.textProperties.numberOfLines = 0
        }
        cell.contentConfiguration = config
        return cell
    }
}

// MARK: - Inline edit VC

/// Minimal edit form pushed when the user taps Edit on a detail view.
final class LearningContentEditViewController: UIViewController {

    private let content:    LearningContent
    private let service:    LearningContentService
    private let onSaved:    () -> Void

    private let titleField    = UITextField()
    private let categoryField = UITextField()
    private let bodyView      = UITextView()

    init(content: LearningContent, service: LearningContentService, onSaved: @escaping () -> Void) {
        self.content  = content
        self.service  = service
        self.onSaved  = onSaved
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Edit Article"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save", style: .done, target: self, action: #selector(saveTapped)
        )

        titleField.text    = content.title
        categoryField.text = content.category
        bodyView.text      = content.body

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])

        for (label, field) in [("Title", titleField), ("Category", categoryField)] {
            let lbl = UILabel()
            lbl.text = label
            lbl.font = UIFont.preferredFont(forTextStyle: .caption1)
            lbl.textColor = .secondaryLabel
            (field as UITextField).borderStyle = .roundedRect
            stack.addArrangedSubview(lbl)
            stack.addArrangedSubview(field)
        }
        let lbl = UILabel()
        lbl.text = "Body"
        lbl.font = UIFont.preferredFont(forTextStyle: .caption1)
        lbl.textColor = .secondaryLabel
        bodyView.font = UIFont.preferredFont(forTextStyle: .body)
        bodyView.layer.borderColor = UIColor.separator.cgColor
        bodyView.layer.borderWidth = 0.5
        bodyView.layer.cornerRadius = 8
        bodyView.isScrollEnabled = false
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        bodyView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        stack.addArrangedSubview(lbl)
        stack.addArrangedSubview(bodyView)
    }

    @objc private func saveTapped() {
        let t = titleField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let b = bodyView.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !t.isEmpty else {
            let a = UIAlertController(title: "Error", message: "Title is required.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default)); present(a, animated: true); return
        }
        guard !b.isEmpty else {
            let a = UIAlertController(title: "Error", message: "Body is required.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default)); present(a, animated: true); return
        }
        let cat = categoryField.text?.trimmingCharacters(in: .whitespaces)
        guard let actor = AuthService.shared.currentUser else {
            let a = UIAlertController(title: "Error", message: "You must be logged in to edit content.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default)); present(a, animated: true); return
        }
        do {
            try service.update(contentID: content.id, title: t, body: b,
                               category: cat?.isEmpty == false ? cat : nil,
                               actor: actor)
            onSaved()
            navigationController?.popViewController(animated: true)
        } catch {
            let a = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default)); present(a, animated: true)
        }
    }
}
