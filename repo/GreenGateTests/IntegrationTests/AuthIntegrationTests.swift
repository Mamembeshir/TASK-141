import XCTest
import CoreData
@testable import GreenGate

/// End-to-end auth flows against an in-memory Core Data store.
/// The Keychain is real (shared across tests), so each test creates users
/// with unique UUIDs — which AuthService.register() always does.
final class AuthIntegrationTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var createdUserIDs: [UUID] = []

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = self.expectation(description: "store")
        container.loadPersistentStores { _, err in
            XCTAssertNil(err); exp.fulfill()
        }
        waitForExpectations(timeout: 5)
        context = container.viewContext
        // Reset session state between tests.
        AuthService.shared.logout(context: context)
    }

    override func tearDownWithError() throws {
        // Remove keychain entries created during the test.
        for id in createdUserIDs {
            KeychainHelper.shared.deletePasswordHash(for: id.uuidString)
        }
        createdUserIDs.removeAll()
        AuthService.shared.logout(context: context)
        context = nil
        container = nil
    }

    // MARK: - Helpers

    private func uniqueUsername(_ base: String) -> String {
        "\(base)_\(UUID().uuidString.prefix(8))"
    }

    @discardableResult
    private func register(username: String, password: String, role: Role = .cashier) throws -> User {
        let user = try AuthService.shared.register(
            username: username, password: password, role: role,
            actorID: nil, context: context
        )
        createdUserIDs.append(user.id)
        return user
    }

    // MARK: - Create → login → success

    func test_register_then_login_succeeds() throws {
        let uname = uniqueUsername("alice")
        let created = try register(username: uname, password: "Password1", role: .cashier)

        let loggedIn = try AuthService.shared.login(
            username: uname, password: "Password1", context: context
        )
        XCTAssertEqual(loggedIn.id, created.id)
        XCTAssertEqual(loggedIn.failedLoginCount, 0)
        XCTAssertEqual(AuthService.shared.currentUser?.id, created.id)
    }

    // MARK: - Password rule (AUTH-01)

    func test_register_weakPassword_throws() {
        let uname = uniqueUsername("weak")
        XCTAssertThrowsError(
            try AuthService.shared.register(
                username: uname, password: "short", role: .cashier,
                actorID: nil, context: context
            )
        ) { err in
            XCTAssertTrue(err is AuthError)
            if case AuthError.passwordTooWeak = (err as! AuthError) { } else {
                XCTFail("expected passwordTooWeak, got \(err)")
            }
        }
    }

    func test_register_duplicateUsername_throws() throws {
        let uname = uniqueUsername("dup")
        _ = try register(username: uname, password: "Password1")
        XCTAssertThrowsError(try register(username: uname, password: "Password1")) { err in
            guard case AuthError.usernameTaken = (err as? AuthError) ?? .invalidCredentials else {
                return XCTFail("expected usernameTaken, got \(err)")
            }
        }
    }

    // MARK: - Lockout (AUTH-03) — 5 failures → locked

    func test_fiveFailedLogins_locksAccount() throws {
        let uname = uniqueUsername("bob")
        try register(username: uname, password: "Password1")

        // Attempts 1..4 — invalidCredentials.
        for i in 1...4 {
            XCTAssertThrowsError(
                try AuthService.shared.login(
                    username: uname, password: "WrongPass1", context: context
                )
            ) { err in
                guard case AuthError.invalidCredentials = (err as? AuthError) ?? .biometricFailed else {
                    return XCTFail("attempt \(i): expected invalidCredentials, got \(err)")
                }
            }
        }

        // 5th attempt — now locked.
        XCTAssertThrowsError(
            try AuthService.shared.login(
                username: uname, password: "WrongPass1", context: context
            )
        ) { err in
            guard case AuthError.accountLocked = (err as? AuthError) ?? .biometricFailed else {
                return XCTFail("expected accountLocked, got \(err)")
            }
        }

        // Subsequent attempts with the CORRECT password are still refused
        // while the lockout is active.
        XCTAssertThrowsError(
            try AuthService.shared.login(
                username: uname, password: "Password1", context: context
            )
        ) { err in
            guard case AuthError.accountLocked = (err as? AuthError) ?? .biometricFailed else {
                return XCTFail("expected accountLocked after success during lockout, got \(err)")
            }
        }
    }

    func test_failedLogins_resetAfterSuccess() throws {
        let uname = uniqueUsername("carol")
        try register(username: uname, password: "Password1")

        _ = try? AuthService.shared.login(username: uname, password: "Nope12345", context: context)
        _ = try? AuthService.shared.login(username: uname, password: "Nope12345", context: context)

        _ = try AuthService.shared.login(username: uname, password: "Password1", context: context)

        let user = try XCTUnwrap(AuthService.shared.currentUser)
        XCTAssertEqual(user.failedLoginCount, 0)
        XCTAssertNil(user.lockedUntil)
    }

    // MARK: - Admin → Cashier → can login

    func test_adminCreatesCashier_cashierCanLogin() throws {
        let adminName = uniqueUsername("admin")
        let cashierName = uniqueUsername("cash")

        let admin = try register(username: adminName, password: "AdminPass1", role: .admin)
        _ = try AuthService.shared.login(username: adminName, password: "AdminPass1", context: context)
        XCTAssertEqual(AuthService.shared.currentUser?.id, admin.id)

        // Admin creates a cashier.
        let cashier = try AuthService.shared.register(
            username: cashierName,
            password: "CashPass12",
            role: .cashier,
            actorID: admin.id,
            context: context
        )
        createdUserIDs.append(cashier.id)
        XCTAssertEqual(cashier.role, Role.cashier.rawValue)

        // Admin logs out.
        AuthService.shared.logout(context: context)
        XCTAssertNil(AuthService.shared.currentUser)

        // Cashier logs in.
        let loggedIn = try AuthService.shared.login(
            username: cashierName, password: "CashPass12", context: context
        )
        XCTAssertEqual(loggedIn.id, cashier.id)
        XCTAssertEqual(loggedIn.role, Role.cashier.rawValue)
    }

    // MARK: - Audit trail

    func test_login_writesAuditEntries() throws {
        let uname = uniqueUsername("audit")
        let user = try register(username: uname, password: "Password1")

        _ = try AuthService.shared.login(username: uname, password: "Password1", context: context)

        let fetch = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        fetch.predicate = NSPredicate(format: "entityID == %@ AND action == %@",
                                      user.id as CVarArg, AuditAction.login)
        let logs = try context.fetch(fetch)
        XCTAssertGreaterThanOrEqual(logs.count, 1)
    }

    func test_failedLogin_writesFailedAuditEntry() throws {
        let uname = uniqueUsername("auditfail")
        let user = try register(username: uname, password: "Password1")

        _ = try? AuthService.shared.login(username: uname, password: "Wrong1234", context: context)

        let fetch = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        fetch.predicate = NSPredicate(format: "entityID == %@ AND action == %@",
                                      user.id as CVarArg,
                                      AuthService.AuthAuditAction.loginFailed)
        let logs = try context.fetch(fetch)
        XCTAssertEqual(logs.count, 1)
    }

    // MARK: - Biometric gating (AUTH-04)

    func test_biometric_withoutPriorLogin_failsWithSessionExpired() {
        let exp = expectation(description: "biometric")
        AuthService.shared.biometricAuth { result in
            if case .failure(let err) = result {
                switch err {
                case .sessionExpired, .biometricNotAvailable:
                    break  // acceptable — either gate works
                default:
                    XCTFail("unexpected error: \(err)")
                }
            } else {
                XCTFail("expected failure without prior login")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    // MARK: - Admin set status

    func test_setStatus_locked_thenActive_resetsCounters() throws {
        let uname = uniqueUsername("setstatus")
        let user = try register(username: uname, password: "Password1")

        // setStatus is admin-only; use a real admin actor to satisfy the check.
        let adminName = uniqueUsername("setstatusadmin")
        let admin = try register(username: adminName, password: "AdminPass1", role: .admin)

        try AuthService.shared.setStatus(.locked, for: user, actorID: admin.id, context: context)
        XCTAssertEqual(user.status, UserStatus.locked.rawValue)
        XCTAssertNotNil(user.lockedUntil)

        try AuthService.shared.setStatus(.active, for: user, actorID: admin.id, context: context)
        XCTAssertEqual(user.status, UserStatus.active.rawValue)
        XCTAssertNil(user.lockedUntil)
        XCTAssertEqual(user.failedLoginCount, 0)
    }

    func test_setStatus_nonAdmin_throws() throws {
        let uname = uniqueUsername("setstatusnon")
        let user = try register(username: uname, password: "Password1", role: .cashier)

        XCTAssertThrowsError(
            try AuthService.shared.setStatus(.locked, for: user, actorID: user.id, context: context)
        ) { err in
            guard case AuthError.insufficientPermissions = (err as? AuthError) ?? .invalidCredentials else {
                return XCTFail("expected insufficientPermissions, got \(err)")
            }
        }
    }
}
