import UIKit

/// Password login screen. Shows a FaceID/TouchID button when a biometric
/// sensor is available and the current process already has a logged-in user
/// (AUTH-04). Calls `onLoginSuccess` with the authenticated user.
final class LoginViewController: UIViewController {

    // MARK: - Callback

    var onLoginSuccess: ((User) -> Void)?

    // MARK: - Views

    let titleLabel     = UILabel()
    let usernameField  = UITextField()
    let passwordField  = UITextField()
    let errorLabel     = UILabel()
    let signInButton   = UIButton(type: .system)
    let biometricButton = UIButton(type: .system)

    private let stack = UIStackView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "SurfacePrimary") ?? .systemBackground
        buildViews()
        updateBiometricButtonVisibility()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        usernameField.becomeFirstResponder()
    }

    // MARK: - Layout

    private func buildViews() {
        titleLabel.text = "Sign in to GreenGate"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        usernameField.placeholder = "Username"
        usernameField.borderStyle = .roundedRect
        usernameField.autocapitalizationType = .none
        usernameField.autocorrectionType = .no
        usernameField.textContentType = .username
        usernameField.returnKeyType = .next
        usernameField.delegate = self
        usernameField.font = .preferredFont(forTextStyle: .body)
        usernameField.adjustsFontForContentSizeCategory = true
        usernameField.accessibilityIdentifier = "login.username"

        passwordField.placeholder = "Password"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .go
        passwordField.delegate = self
        passwordField.font = .preferredFont(forTextStyle: .body)
        passwordField.adjustsFontForContentSizeCategory = true
        passwordField.accessibilityIdentifier = "login.password"

        errorLabel.text = " "
        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = UIColor(named: "Danger") ?? .systemRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.accessibilityIdentifier = "login.error"

        signInButton.setTitle("Sign In", for: .normal)
        signInButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        signInButton.titleLabel?.adjustsFontForContentSizeCategory = true
        signInButton.configuration = {
            var c = UIButton.Configuration.filled()
            c.title = "Sign In"
            c.baseBackgroundColor = UIColor(named: "GreenPrimary")
            c.cornerStyle = .medium
            return c
        }()
        signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        signInButton.accessibilityIdentifier = "login.signIn"

        let biometricTitle: String
        switch BiometricHelper.availableType {
        case .faceID:  biometricTitle = "Use Face ID"
        case .touchID: biometricTitle = "Use Touch ID"
        case .none:    biometricTitle = "Use Biometrics"
        }
        biometricButton.configuration = {
            var c = UIButton.Configuration.tinted()
            c.title = biometricTitle
            c.baseForegroundColor = UIColor(named: "GreenPrimary")
            return c
        }()
        biometricButton.addTarget(self, action: #selector(biometricTapped), for: .touchUpInside)
        biometricButton.accessibilityIdentifier = "login.biometric"

        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(28, after: titleLabel)
        stack.addArrangedSubview(usernameField)
        stack.addArrangedSubview(passwordField)
        stack.addArrangedSubview(errorLabel)
        stack.addArrangedSubview(signInButton)
        stack.addArrangedSubview(biometricButton)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
    }

    private func updateBiometricButtonVisibility() {
        // AUTH-04: biometric unlock is only meaningful once a password login
        // has happened in this session.
        let canUseBiometric = BiometricHelper.isAvailable && AuthService.shared.currentUser != nil
        biometricButton.isHidden = !canUseBiometric
    }

    // MARK: - Actions

    @objc private func signInTapped() {
        view.endEditing(true)
        let username = usernameField.text ?? ""
        let password = passwordField.text ?? ""

        guard !username.isEmpty, !password.isEmpty else {
            showError("Enter username and password.")
            return
        }

        do {
            let user = try AuthService.shared.login(
                username: username,
                password: password,
                context: CoreDataStack.shared.viewContext
            )
            errorLabel.text = " "
            HapticHelper.success()
            passwordField.text = ""
            updateBiometricButtonVisibility()
            onLoginSuccess?(user)
        } catch let e as AuthError {
            HapticHelper.error()
            showError(e.errorDescription ?? "Login failed.")
        } catch {
            HapticHelper.error()
            showError(error.localizedDescription)
        }
    }

    @objc private func biometricTapped() {
        AuthService.shared.biometricAuth(reason: "Unlock GreenGate") { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let user):
                self.errorLabel.text = " "
                self.onLoginSuccess?(user)
            case .failure(let err):
                self.showError(err.errorDescription ?? "Biometric authentication failed.")
            }
        }
    }

    private func showError(_ message: String) {
        errorLabel.text = message
    }
}

// MARK: - UITextFieldDelegate

extension LoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === usernameField {
            passwordField.becomeFirstResponder()
        } else {
            signInTapped()
        }
        return true
    }
}
