import UIKit

/// Create/edit a property listing. Emits PropertyChangeHistory rows via
/// PropertyService.update on edits.
final class PropertyFormViewController: UIViewController {

    private let listing: PropertyListing?
    private let service: PropertyService
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let title_        = UITextField()
    private let line1         = UITextField()
    private let line2         = UITextField()
    private let city          = UITextField()
    private let state_        = UITextField()
    private let zip           = UITextField()
    private let sqft          = UITextField()
    private let amenities     = UITextField()
    private let rent          = UITextField()
    private let deposit       = UITextField()
    private let leaseMonths   = UITextField()
    private let availableFrom = UIDatePicker()

    init(listing: PropertyListing?, service: PropertyService = .shared) {
        self.listing = listing
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = listing == nil ? "New Listing" : "Edit Listing"
        view.backgroundColor = UIColor(named: "SurfaceGrouped")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(saveTapped)
        )
        setupLayout()
        populateFromListing()
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
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

        [title_, line1, line2, city, state_, zip, sqft, amenities,
         rent, deposit, leaseMonths].forEach {
            $0.borderStyle = .roundedRect
            $0.font = UIFont.preferredFont(forTextStyle: .body)
            $0.adjustsFontForContentSizeCategory = true
        }
        title_.placeholder        = "Title *"
        line1.placeholder         = "Address line 1 *"
        line2.placeholder         = "Address line 2"
        city.placeholder          = "City *"
        state_.placeholder        = "State (2-char) *"
        state_.autocapitalizationType = .allCharacters
        zip.placeholder           = "ZIP (5 or 5+4) *"
        zip.keyboardType          = .numbersAndPunctuation
        sqft.placeholder          = "Sq footage *"
        sqft.keyboardType         = .numberPad
        amenities.placeholder     = "Amenities (comma-separated)"
        rent.placeholder          = "Rent cents *"
        rent.keyboardType         = .numberPad
        deposit.placeholder       = "Deposit cents *"
        deposit.keyboardType      = .numberPad
        leaseMonths.placeholder   = "Lease months *"
        leaseMonths.keyboardType  = .numberPad

        availableFrom.datePickerMode = .date
        availableFrom.preferredDatePickerStyle = .inline

        let availableLabel = UILabel()
        availableLabel.text = "Available from"
        availableLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)

        for v in [title_, line1, line2, city, state_, zip, sqft, amenities,
                  rent, deposit, leaseMonths, availableLabel, availableFrom] {
            stack.addArrangedSubview(v)
        }
    }

    private func populateFromListing() {
        guard let l = listing else { return }
        title_.text = l.title
        line1.text = l.addressLine1
        line2.text = l.addressLine2
        city.text = l.city
        state_.text = l.state
        zip.text = l.zipCode
        sqft.text = "\(l.squareFootage)"
        amenities.text = l.amenitiesArray.joined(separator: ", ")
        rent.text = "\(l.rentCents)"
        deposit.text = "\(l.depositCents)"
        leaseMonths.text = "\(l.leaseTermMonths)"
        availableFrom.date = l.availableFrom
    }

    @objc private func saveTapped() {
        guard let actor = AuthService.shared.currentUser else {
            let alert = UIAlertController(title: "Error",
                                          message: "You must be logged in to save a listing.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let amenitiesArray = (amenities.text ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        do {
            if let listing = listing {
                let input = PropertyService.UpdateInput(
                    title: title_.text,
                    addressLine1: line1.text,
                    addressLine2: Optional.some(line2.text?.isEmpty == false ? line2.text : nil),
                    city: city.text,
                    state: state_.text,
                    zipCode: zip.text,
                    squareFootage: Int32(sqft.text ?? ""),
                    amenities: amenitiesArray,
                    rentCents: Int64(rent.text ?? ""),
                    depositCents: Int64(deposit.text ?? ""),
                    leaseMonths: Int16(leaseMonths.text ?? ""),
                    availableFrom: availableFrom.date
                )
                _ = try service.update(listingID: listing.id, input: input, actor: actor)
            } else {
                let input = PropertyService.CreateInput(
                    title: title_.text ?? "",
                    addressLine1: line1.text ?? "",
                    addressLine2: line2.text?.isEmpty == false ? line2.text : nil,
                    city: city.text ?? "",
                    state: state_.text ?? "",
                    zipCode: zip.text ?? "",
                    squareFootage: Int32(sqft.text ?? "") ?? 0,
                    amenities: amenitiesArray,
                    rentCents: Int64(rent.text ?? "") ?? 0,
                    depositCents: Int64(deposit.text ?? "") ?? 0,
                    leaseMonths: Int16(leaseMonths.text ?? "") ?? 0,
                    availableFrom: availableFrom.date
                )
                _ = try service.create(input: input, actor: actor)
            }
            navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "Error", message: error.localizedDescription,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}
