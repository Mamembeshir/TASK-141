import UIKit

/// Create/edit an SPU along with its SKUs. Enforces barcode uniqueness inline
/// as the user types, and commits via `ProductService`.
final class ProductFormViewController: UIViewController {

    // MARK: - Model

    struct SKUDraft {
        var barcode: String = ""
        var stemCount: Int16 = 0
        var wrapType: String = ""
        var color: String = ""
        var priceCents: Int64 = 0
        var isTaxable: Bool = true
        var duplicate: Bool = false
    }

    private let spu: ProductSPU?
    private let service: ProductService
    private let productRepo: ProductRepository

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let nameField = UITextField()
    private let categoryField = UITextField()
    private let descriptionField = UITextField()
    private let nameError = UILabel()
    private let skusStack = UIStackView()

    private var drafts: [SKUDraft] = []
    private var skuRowViews: [SKURowView] = []

    init(spu: ProductSPU? = nil, service: ProductService = .shared) {
        self.spu = spu
        self.service = service
        self.productRepo = ProductRepository(context: CoreDataStack.shared.viewContext)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = spu == nil ? "New Product" : "Edit Product"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(saveTapped)
        )

        setupLayout()
        seedFromSPU()
        if drafts.isEmpty && spu == nil { addSKU() }
        rebuildSKURows()
    }

    // MARK: - Layout

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        stack.addArrangedSubview(label("Name *"))
        styleField(nameField, placeholder: "Spring Bouquet")
        stack.addArrangedSubview(nameField)
        nameError.font = UIFont.preferredFont(forTextStyle: .caption1)
        nameError.textColor = UIColor(named: "Danger")
        nameError.isHidden = true
        stack.addArrangedSubview(nameError)

        stack.addArrangedSubview(label("Category"))
        styleField(categoryField, placeholder: "Flowers")
        stack.addArrangedSubview(categoryField)

        stack.addArrangedSubview(label("Description"))
        styleField(descriptionField, placeholder: "Optional")
        stack.addArrangedSubview(descriptionField)

        let skusHeader = label("SKUs")
        skusHeader.font = UIFont.preferredFont(forTextStyle: .headline)
        stack.addArrangedSubview(skusHeader)

        skusStack.axis = .vertical
        skusStack.spacing = 16
        stack.addArrangedSubview(skusStack)

        let addButton = UIButton(type: .system)
        addButton.setTitle("+ Add SKU", for: .normal)
        addButton.addTarget(self, action: #selector(addSKUTapped), for: .touchUpInside)
        stack.addArrangedSubview(addButton)
    }

    private func label(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = UIFont.preferredFont(forTextStyle: .subheadline)
        l.adjustsFontForContentSizeCategory = true
        return l
    }

    private func styleField(_ f: UITextField, placeholder: String) {
        f.borderStyle = .roundedRect
        f.placeholder = placeholder
        f.font = UIFont.preferredFont(forTextStyle: .body)
        f.adjustsFontForContentSizeCategory = true
    }

    // MARK: - SKU rows

    @objc private func addSKUTapped() {
        addSKU()
        rebuildSKURows()
    }

    private func addSKU() { drafts.append(SKUDraft()) }

    private func rebuildSKURows() {
        for v in skuRowViews { v.removeFromSuperview() }
        skuRowViews.removeAll()
        for (idx, _) in drafts.enumerated() {
            let row = SKURowView()
            row.index = idx
            row.onChange = { [weak self] draft in
                guard let self = self else { return }
                self.drafts[idx] = draft
                self.validateBarcode(at: idx)
            }
            row.configure(draft: drafts[idx], isEditing: spu != nil && idx < (spu?.skusArray.count ?? 0))
            skuRowViews.append(row)
            skusStack.addArrangedSubview(row)
        }
    }

    private func seedFromSPU() {
        guard let spu = spu else { return }
        nameField.text = spu.name
        categoryField.text = spu.category
        descriptionField.text = spu.description_
        drafts = spu.skusArray.map { sku in
            SKUDraft(
                barcode: sku.barcode,
                stemCount: sku.stemCount,
                wrapType: sku.wrapType ?? "",
                color: sku.color ?? "",
                priceCents: sku.priceCents,
                isTaxable: sku.isTaxable
            )
        }
    }

    // MARK: - Validation

    /// PROD-02: barcode must be non-empty and unique across all SKUs.
    /// Checks both in-form duplicates and existing DB records.
    private func validateBarcode(at index: Int) {
        var draft = drafts[index]
        let code = draft.barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty {
            draft.duplicate = false
        } else {
            let inFormDup = drafts.enumerated().contains { i, d in
                i != index && d.barcode.trimmingCharacters(in: .whitespacesAndNewlines) == code
            }
            let existingID: UUID? = {
                guard let spu = spu, index < spu.skusArray.count else { return nil }
                return spu.skusArray[index].id
            }()
            let dbDup = (try? productRepo.barcodeExists(code, excludingSKU: existingID)) ?? false
            draft.duplicate = inFormDup || dbDup
        }
        drafts[index] = draft
        skuRowViews[index].configure(draft: draft, isEditing: false)
    }

    // MARK: - Save

    @objc private func saveTapped() {
        let name = nameField.text ?? ""
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            nameError.text = "Name is required."
            nameError.isHidden = false
            return
        }
        nameError.isHidden = true

        for (idx, d) in drafts.enumerated() {
            let code = d.barcode.trimmingCharacters(in: .whitespacesAndNewlines)
            if code.isEmpty || d.duplicate {
                skuRowViews[idx].configure(draft: d, isEditing: false)
                return
            }
        }

        guard let actor = AuthService.shared.currentUser else {
            let alert = UIAlertController(title: "Error",
                                          message: "You must be signed in to save products.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        do {
            let spuID: UUID
            if let existing = spu {
                existing.name = name
                existing.category = categoryField.text
                existing.description_ = descriptionField.text
                existing.updatedAt = Date()
                existing.version += 1
                AuditService.shared.log(
                    actorID: actor.id, action: AuditAction.update,
                    entityType: "ProductSPU", entityID: existing.id,
                    afterJSON: "{\"name\":\"\(name)\"}",
                    context: CoreDataStack.shared.viewContext
                )
                try CoreDataStack.shared.save(context: CoreDataStack.shared.viewContext)
                spuID = existing.id
            } else {
                let created = try service.createSPU(
                    name: name,
                    description: descriptionField.text,
                    category: categoryField.text,
                    actor: actor
                )
                spuID = created.id
            }

            // New drafts only; edits to existing SKUs are not in scope for this
            // screen (see Inventory screen for stock + detail for status changes).
            let existingCount = spu?.skusArray.count ?? 0
            for d in drafts.suffix(from: min(existingCount, drafts.count)) {
                try service.createSKU(
                    spuID: spuID,
                    barcode: d.barcode.trimmingCharacters(in: .whitespacesAndNewlines),
                    stemCount: d.stemCount,
                    wrapType: d.wrapType.isEmpty ? nil : d.wrapType,
                    color: d.color.isEmpty ? nil : d.color,
                    priceCents: d.priceCents,
                    isTaxable: d.isTaxable,
                    actor: actor
                )
            }
            navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "Error",
                                          message: error.localizedDescription,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

// MARK: - SKU Row View

final class SKURowView: UIView {

    var index: Int = 0
    var onChange: ((ProductFormViewController.SKUDraft) -> Void)?

    private let barcode = UITextField()
    private let stem    = UITextField()
    private let wrap    = UITextField()
    private let color   = UITextField()
    private let price   = UITextField()
    private let taxable = UISwitch()
    private let barcodeError = UILabel()

    private var draft = ProductFormViewController.SKUDraft()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "SurfaceElevated")
        layer.cornerRadius = 12
        layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        [barcode, stem, wrap, color, price].forEach {
            $0.borderStyle = .roundedRect
            $0.font = UIFont.preferredFont(forTextStyle: .body)
            $0.adjustsFontForContentSizeCategory = true
            $0.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        }
        barcode.placeholder = "Barcode *"
        stem.placeholder = "Stems"
        stem.keyboardType = .numberPad
        wrap.placeholder = "Wrap type"
        color.placeholder = "Color"
        price.placeholder = "Price (cents)"
        price.keyboardType = .numberPad

        taxable.isOn = true
        taxable.addTarget(self, action: #selector(taxChanged), for: .valueChanged)
        let taxLabel = UILabel()
        taxLabel.text = "Taxable"
        taxLabel.font = UIFont.preferredFont(forTextStyle: .footnote)

        barcodeError.font = UIFont.preferredFont(forTextStyle: .caption1)
        barcodeError.textColor = UIColor(named: "Danger")
        barcodeError.isHidden = true

        let taxRow = UIStackView(arrangedSubviews: [taxLabel, taxable])
        taxRow.axis = .horizontal
        taxRow.spacing = 8

        let stack = UIStackView(arrangedSubviews: [barcode, barcodeError, stem, wrap, color, price, taxRow])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }

    func configure(draft: ProductFormViewController.SKUDraft, isEditing: Bool) {
        self.draft = draft
        barcode.text = draft.barcode
        stem.text    = draft.stemCount == 0 ? "" : "\(draft.stemCount)"
        wrap.text    = draft.wrapType
        color.text   = draft.color
        price.text   = draft.priceCents == 0 ? "" : "\(draft.priceCents)"
        taxable.isOn = draft.isTaxable
        barcode.layer.borderColor = draft.duplicate
            ? (UIColor(named: "Danger")?.cgColor ?? UIColor.red.cgColor)
            : UIColor.clear.cgColor
        barcode.layer.borderWidth = draft.duplicate ? 1 : 0
        barcodeError.isHidden = !draft.duplicate
        barcodeError.text = draft.duplicate ? "This barcode is already in use." : nil
        if isEditing { barcode.isEnabled = false }
    }

    @objc private func textChanged() {
        draft.barcode    = barcode.text ?? ""
        draft.stemCount  = Int16(stem.text ?? "") ?? 0
        draft.wrapType   = wrap.text ?? ""
        draft.color      = color.text ?? ""
        draft.priceCents = Int64(price.text ?? "") ?? 0
        onChange?(draft)
    }

    @objc private func taxChanged() {
        draft.isTaxable = taxable.isOn
        onChange?(draft)
    }
}
