import UIKit
import UniformTypeIdentifiers

/// Import / Export UI. Import: file picker → validation → summary row ("7
/// imported, 3 rejected") + per-row error table. Export: entity picker,
/// status filter, mask toggle, export button.
final class ImportExportViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let service: ImportExportService

    private var lastReport: ImportExportService.ImportReport?
    private var maskSensitive  = true
    private var exportAfterDate: Date?   // nil = no date filter

    init(service: ImportExportService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Import / Export"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        setupTableView()
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

    // MARK: - Import

    private func presentDocumentPicker() {
        let types: [UTType] = [.commaSeparatedText, .spreadsheet]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func runImport(from url: URL) {
        guard let actor = AuthService.shared.currentUser else {
            showError("You must be signed in to import products.")
            return
        }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }

        // Check size: large files go to the background task so the app isn't
        // blocked while the system terminates foreground work.
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if fileSize > AppConfiguration.backgroundImportThresholdBytes {
            scheduleBackgroundImport(from: url, actor: actor)
        } else {
            runForegroundImport(from: url, actor: actor)
        }
    }

    /// Foreground path for small files (≤ 512 KB).
    private func runForegroundImport(from url: URL, actor: User) {
        do {
            let report: ImportExportService.ImportReport
            let ext = url.pathExtension.lowercased()
            if ext == "xlsx" {
                report = try service.importProductsXLSX(at: url, actor: actor)
            } else {
                report = try service.importProductsCSV(at: url, actor: actor)
            }
            lastReport = report
            tableView.reloadData()
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Background path for large files (> 512 KB).
    /// Copies the file to a stable staging directory so `BulkImportTask` can
    /// access it after the security-scoped URL expires, then schedules the task.
    private func scheduleBackgroundImport(from url: URL, actor: User) {
        AppConfiguration.createDirectoriesIfNeeded()
        let dest = AppConfiguration.importStagingDirectory
            .appendingPathComponent(url.lastPathComponent)
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: url, to: dest)
        } catch {
            // Copy failed — fall back to foreground import.
            runForegroundImport(from: url, actor: actor)
            return
        }
        BulkImportTask.schedulePendingImport(fileURL: dest, actorID: actor.id)
        let alert = UIAlertController(
            title: "Import Scheduled",
            message: "This file is large and will be imported in the background when the device is idle. You'll see results next time you open this screen.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Export

    private func runExport() {
        guard let actor = AuthService.shared.currentUser else {
            showError("You must be signed in to export products.")
            return
        }
        do {
            let url = try service.exportProductsCSV(
                statusFilter: .listed,
                createdAfter: exportAfterDate,
                maskSensitive: maskSensitive,
                actorID: actor.id
            )
            let alert = UIAlertController(title: "Export saved",
                                          message: url.lastPathComponent,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func presentDateFilterPicker() {
        let alert = UIAlertController(title: "Created After",
                                      message: "Only export products created on or after this date.",
                                      preferredStyle: .alert)
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .wheels
        picker.date = exportAfterDate ?? Date()
        picker.translatesAutoresizingMaskIntoConstraints = false
        alert.view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 80),
            picker.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            picker.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -60),
        ])
        alert.addAction(UIAlertAction(title: "Clear Filter", style: .destructive) { _ in
            self.exportAfterDate = nil
            self.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { _ in
            self.exportAfterDate = picker.date
            self.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension ImportExportViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        lastReport != nil ? 3 : 2
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Import"
        case 1: return "Export (status = LISTED)"
        case 2: return "Last Import Report"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 3   // mask toggle + date filter + export button
        case 2: return 1 + (lastReport?.errors.count ?? 0)
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        switch indexPath.section {
        case 0:
            config.text = "Import Products (CSV / XLSX)"
            config.image = UIImage(systemName: "square.and.arrow.down")
            cell.accessoryType = .disclosureIndicator
        case 1:
            switch indexPath.row {
            case 0:
                config.text = "Mask sensitive fields"
                let s = UISwitch()
                s.isOn = maskSensitive
                s.addTarget(self, action: #selector(maskToggled(_:)), for: .valueChanged)
                cell.accessoryView = s
                cell.selectionStyle = .none
            case 1:
                let fmt = DateFormatter()
                fmt.dateStyle = .medium; fmt.timeStyle = .none
                let label = exportAfterDate.map { "Created after \(fmt.string(from: $0))" }
                           ?? "No date filter"
                config.text  = "Date filter"
                config.secondaryText = label
                cell.accessoryType   = .disclosureIndicator
            default:
                config.text = "Export products.csv"
                config.image = UIImage(systemName: "square.and.arrow.up")
                cell.accessoryType = .disclosureIndicator
            }
        case 2:
            if indexPath.row == 0 {
                let r = lastReport!
                config.text = "Summary"
                config.secondaryText = "\(r.imported) imported · \(r.rejected) rejected"
            } else {
                let err = lastReport!.errors[indexPath.row - 1]
                config.text = "Row \(err.row) · \(err.field)"
                config.secondaryText = "\(err.reason) (score \(err.score))"
                config.textProperties.color = UIColor(named: "Danger") ?? .systemRed
            }
        default: break
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch (indexPath.section, indexPath.row) {
        case (0, 0): presentDocumentPicker()
        case (1, 1): presentDateFilterPicker()
        case (1, 2): runExport()
        default: break
        }
    }

    @objc private func maskToggled(_ sw: UISwitch) { maskSensitive = sw.isOn }
}

extension ImportExportViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        runImport(from: url)
    }
}
