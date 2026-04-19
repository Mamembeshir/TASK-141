import UIKit
import AVFoundation
import CoreData

/// Main POS screen: AVFoundation barcode scanner preview (optional), a manual
/// barcode-entry field, and an embedded cart with a real-time total.
final class POSViewController: UIViewController {

    private let emptyState = EmptyStateView()
    private let cart: CartViewController
    private let totalLabel = CurrencyLabel()
    private let bottomToolbar = UIToolbar()
    private let barcodeField = UITextField()

    private let service: POSService
    private var order: Order?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let scannerContainer = UIView()

    init(service: POSService = .shared) {
        self.service = service
        self.cart = CartViewController(service: service)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "POS"
        view.backgroundColor = UIColor(named: "SurfacePrimary")
        navigationItem.largeTitleDisplayMode = .always
        setupLayout()
        openNewOrderIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    // MARK: - Layout

    private func setupLayout() {
        // Manual barcode entry
        barcodeField.placeholder = "Scan or enter barcode"
        barcodeField.borderStyle = .roundedRect
        barcodeField.font = UIFont.preferredFont(forTextStyle: .body)
        barcodeField.adjustsFontForContentSizeCategory = true
        barcodeField.returnKeyType = .search
        barcodeField.translatesAutoresizingMaskIntoConstraints = false
        barcodeField.addTarget(self, action: #selector(barcodeSubmitted), for: .primaryActionTriggered)
        view.addSubview(barcodeField)

        scannerContainer.backgroundColor = .black
        scannerContainer.layer.cornerRadius = 12
        scannerContainer.clipsToBounds = true
        scannerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scannerContainer)

        // Cart child
        addChild(cart)
        cart.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cart.view)
        cart.didMove(toParent: self)
        cart.onTotalsChanged = { [weak self] order in
            self?.totalLabel.amountCents = order.totalCents
        }

        // Total
        totalLabel.applyPOSTotalStyle()
        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(totalLabel)

        // Bottom toolbar
        bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomToolbar)

        let scan = UIBarButtonItem(image: UIImage(systemName: "barcode.viewfinder"),
                                   style: .plain, target: self, action: #selector(scanTapped))
        let park = UIBarButtonItem(title: "Park", style: .plain, target: self, action: #selector(parkTapped))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let pay  = UIBarButtonItem(title: "Pay", style: .done, target: self, action: #selector(payTapped))
        scan.accessibilityLabel = "Scan Barcode"
        park.accessibilityLabel = "Park Order"
        pay.accessibilityLabel  = "Process Payment"
        bottomToolbar.setItems([scan, flex, park, flex, pay], animated: false)

        let parked  = UIBarButtonItem(image: UIImage(systemName: "tray.2"),
                                      style: .plain, target: self, action: #selector(showParked))
        let returns = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.backward"),
                                      style: .plain, target: self, action: #selector(showReturns))
        navigationItem.rightBarButtonItems = [parked, returns]

        NSLayoutConstraint.activate([
            barcodeField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            barcodeField.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            barcodeField.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            scannerContainer.topAnchor.constraint(equalTo: barcodeField.bottomAnchor, constant: 8),
            scannerContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scannerContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            scannerContainer.heightAnchor.constraint(equalToConstant: 180),

            cart.view.topAnchor.constraint(equalTo: scannerContainer.bottomAnchor, constant: 8),
            cart.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cart.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cart.view.bottomAnchor.constraint(equalTo: totalLabel.topAnchor, constant: -8),

            totalLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            totalLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            totalLabel.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: -8),

            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = scannerContainer.bounds
    }

    private func openNewOrderIfNeeded() {
        guard let cashier = AuthService.shared.currentUser else { return }
        do {
            let o = try service.createOrder(cashier: cashier)
            order = o
            cart.set(order: o)
            totalLabel.amountCents = o.totalCents
        } catch {
            // Silent — user will see the error on first scan attempt.
        }
    }

    // MARK: - Scan handling

    @objc private func barcodeSubmitted() {
        let code = barcodeField.text ?? ""
        barcodeField.text = ""
        processBarcode(code)
    }

    private func processBarcode(_ code: String) {
        guard let order = order else { return }
        do {
            let sku = try service.scanBarcode(code)
            try service.addToCart(orderID: order.id, skuID: sku.id, quantity: 1)
            HapticHelper.success()
            cart.reload()
            totalLabel.amountCents = order.totalCents
        } catch {
            HapticHelper.error()
            showError(error.localizedDescription)
        }
    }

    // MARK: - Scanner

    @objc private func scanTapped() {
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
            return
        }
        startScanner()
    }

    private func startScanner() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean13, .ean8, .code128, .qr, .upce]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = scannerContainer.bounds
        scannerContainer.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        scannerContainer.layer.addSublayer(preview)
        previewLayer = preview
        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    // MARK: - Toolbar actions

    @objc private func parkTapped() {
        guard let o = order else { return }
        guard let actor = AuthService.shared.currentUser else {
            showError("You must be signed in to park an order.")
            return
        }
        do {
            try service.parkOrder(orderID: o.id, actor: actor)
            openNewOrderIfNeeded()
            cart.reload()
        } catch { showError(error.localizedDescription) }
    }

    @objc private func payTapped() {
        guard let o = order else { return }
        let vc = CheckoutViewController(order: o, service: service) { [weak self] in
            self?.openNewOrderIfNeeded()
            self?.cart.reload()
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func showParked() {
        navigationController?.pushViewController(ParkedTicketsViewController(), animated: true)
    }

    @objc private func showReturns() {
        navigationController?.pushViewController(ReturnExchangeViewController(), animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension POSViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let m = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = m.stringValue else { return }
        captureSession?.stopRunning()
        processBarcode(code)
    }
}
