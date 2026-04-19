import XCTest
@testable import GreenGate

final class LoginViewTests: XCTestCase {

    func test_viewLoads_withoutCrash() {
        let vc = LoginViewController()
        _ = vc.view
        XCTAssertNotNil(vc.view)
    }

    func test_renders_usernameAndPasswordFields() {
        let vc = LoginViewController()
        _ = vc.view
        XCTAssertEqual(vc.usernameField.accessibilityIdentifier, "login.username")
        XCTAssertEqual(vc.passwordField.accessibilityIdentifier, "login.password")
        XCTAssertTrue(vc.passwordField.isSecureTextEntry)
    }

    func test_renders_signInButton() {
        let vc = LoginViewController()
        _ = vc.view
        XCTAssertEqual(vc.signInButton.accessibilityIdentifier, "login.signIn")
    }

    func test_errorLabel_isEmptyInitially() {
        let vc = LoginViewController()
        _ = vc.view
        XCTAssertEqual(vc.errorLabel.text?.trimmingCharacters(in: .whitespaces), "")
    }

    func test_biometricButton_hidden_whenNoPriorLogin() {
        AuthService.shared.logout(context: CoreDataStack.shared.viewContext)
        let vc = LoginViewController()
        _ = vc.view
        // With no currentUser, AUTH-04 hides the button regardless of sensor.
        XCTAssertTrue(vc.biometricButton.isHidden)
    }

    func test_dynamicType_isEnabled() {
        let vc = LoginViewController()
        _ = vc.view
        XCTAssertTrue(vc.titleLabel.adjustsFontForContentSizeCategory)
        XCTAssertTrue(vc.usernameField.adjustsFontForContentSizeCategory)
        XCTAssertTrue(vc.passwordField.adjustsFontForContentSizeCategory)
    }
}
