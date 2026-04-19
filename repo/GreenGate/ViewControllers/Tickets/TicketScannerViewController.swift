import UIKit
import AVFoundation

/// Gate Attendant's primary screen: AVCaptureSession QR scanner with overlay
/// frame and result banner. ✅ green for SUCCESS, ❌ red for failure, with
/// per-outcome detail. Haptic success/error after every scan.
final class TicketScannerViewController: UIViewController {

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let overlayView  = UIView()
    private let resultBanner = UIView()
    private let resultLabel  = UILabel()
    private let detailLabel  = UILabel()
    private let resumeButton = UIButton(type: .system)
    private let service: TicketService

    init(service: TicketService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Scan Ticket"
        view.backgroundColor = .black
        navigationItem.largeTitleDisplayMode = .never
        setupCameraPreview()
        setupOverlay()
        setupResultBanner()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Camera Setup

    private func setupCameraPreview() {
        let session = AVCaptureSession()
        captureSession = session

        guard let device = AVCaptureDevice.default(for: .video),
              let input  = try? AVCaptureDeviceInput(device: device) else {
            showNoCameraMessage()
            return
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddInput(input) && session.canAddOutput(output) {
            session.addInput(input)
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    private func setupOverlay() {
        overlayView.layer.borderColor = UIColor.white.cgColor
        overlayView.layer.borderWidth = 2
        overlayView.layer.cornerRadius = 12
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            overlayView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            overlayView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.7),
            overlayView.heightAnchor.constraint(equalTo: overlayView.widthAnchor),
        ])
    }

    private func setupResultBanner() {
        resultBanner.translatesAutoresizingMaskIntoConstraints = false
        resultBanner.layer.cornerRadius = 12
        resultBanner.alpha = 0
        view.addSubview(resultBanner)

        for label in [resultLabel, detailLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.adjustsFontForContentSizeCategory = true
            label.textAlignment = .center
            label.textColor = .white
            label.numberOfLines = 0
            resultBanner.addSubview(label)
        }
        resultLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        detailLabel.font = UIFont.preferredFont(forTextStyle: .body)

        resumeButton.setTitle("Scan Next", for: .normal)
        resumeButton.setTitleColor(.white, for: .normal)
        resumeButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        resumeButton.translatesAutoresizingMaskIntoConstraints = false
        resumeButton.addTarget(self, action: #selector(resumeTapped), for: .touchUpInside)
        resultBanner.addSubview(resumeButton)

        NSLayoutConstraint.activate([
            resultBanner.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            resultBanner.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            resultBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            resultLabel.topAnchor.constraint(equalTo: resultBanner.topAnchor, constant: 16),
            resultLabel.leadingAnchor.constraint(equalTo: resultBanner.leadingAnchor, constant: 16),
            resultLabel.trailingAnchor.constraint(equalTo: resultBanner.trailingAnchor, constant: -16),

            detailLabel.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: resultBanner.leadingAnchor, constant: 16),
            detailLabel.trailingAnchor.constraint(equalTo: resultBanner.trailingAnchor, constant: -16),

            resumeButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 12),
            resumeButton.bottomAnchor.constraint(equalTo: resultBanner.bottomAnchor, constant: -16),
            resumeButton.centerXAnchor.constraint(equalTo: resultBanner.centerXAnchor),
        ])
    }

    private func showNoCameraMessage() {
        let label = UILabel()
        label.text = "Camera not available on this device."
        label.textColor = .white
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
    }

    // MARK: - Scan Result Handling

    private func handleScan(payload: String) {
        captureSession?.stopRunning()
        guard let user = AuthService.shared.currentUser else {
            show(success: false, title: "Not Signed In", detail: "Please sign in before scanning tickets.")
            return
        }
        do {
            let outcome = try service.checkIn(qrPayload: payload, scannedBy: user)
            switch outcome {
            case .success(let ticket):
                HapticHelper.success()
                show(success: true,
                     title: "✅ Checked In",
                     detail: "\(ticket.ticketNumber) · \(ticket.holderName ?? "Holder")")
            case .duplicate(let ticket, let by, let at):
                HapticHelper.error()
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                show(success: false,
                     title: "⚠️ Already Checked In",
                     detail: "\(ticket.ticketNumber) — by \(by) at \(formatter.string(from: at))")
            case .expired:
                HapticHelper.error()
                show(success: false,
                     title: "❌ Expired",
                     detail: "Ticket is outside its validity window.")
            case .invalid(let reason):
                HapticHelper.error()
                show(success: false, title: "❌ Invalid", detail: reason)
            }
        } catch {
            HapticHelper.error()
            show(success: false, title: "❌ Error", detail: error.localizedDescription)
        }
    }

    private func show(success: Bool, title: String, detail: String) {
        resultLabel.text = title
        detailLabel.text = detail
        resultBanner.backgroundColor = success
            ? UIColor(named: "Success") ?? .systemGreen
            : UIColor(named: "Danger")  ?? .systemRed
        UIView.animate(withDuration: 0.2) { self.resultBanner.alpha = 1 }
    }

    @objc private func resumeTapped() {
        UIView.animate(withDuration: 0.2) { self.resultBanner.alpha = 0 }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    /// Test hook so view tests can drive the scanner without a camera.
    func _handleScanForTests(payload: String) { handleScan(payload: payload) }
}

extension TicketScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let string = readable.stringValue else { return }
        handleScan(payload: string)
    }
}
