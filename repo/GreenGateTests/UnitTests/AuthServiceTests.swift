import XCTest
@testable import GreenGate

/// AUTH-01 and lockout-threshold unit tests — pure policy checks, no
/// Core Data or Keychain involved.
final class AuthServiceTests: XCTestCase {

    // MARK: - Password validation (AUTH-01)

    func test_passwordValidation_tooShort_isInvalid() {
        XCTAssertFalse(AuthService.isPasswordValid("Short1"))
    }

    func test_passwordValidation_noNumber_isInvalid() {
        XCTAssertFalse(AuthService.isPasswordValid("OnlyLetters"))
    }

    func test_passwordValidation_minimumValid_isValid() {
        // 8 chars, contains a digit.
        XCTAssertTrue(AuthService.isPasswordValid("abcdefg1"))
    }

    func test_passwordValidation_typical_isValid() {
        XCTAssertTrue(AuthService.isPasswordValid("GreenGate1"))
    }

    func test_passwordValidation_empty_isInvalid() {
        XCTAssertFalse(AuthService.isPasswordValid(""))
    }

    func test_passwordValidation_longPasswordWithNumber_isValid() {
        XCTAssertTrue(AuthService.isPasswordValid("a-very-long-password-9"))
    }

    func test_passwordValidation_digitsOnly_eightLong_isValid() {
        XCTAssertTrue(AuthService.isPasswordValid("12345678"))
    }

    // MARK: - Lockout policy

    func test_lockoutPolicy_hasFiveAttempts() {
        XCTAssertEqual(AuthService.maxFailedAttempts, 5)
    }

    func test_lockoutPolicy_durationIsPositive() {
        XCTAssertGreaterThan(AuthService.lockoutDuration, 0)
    }
}
