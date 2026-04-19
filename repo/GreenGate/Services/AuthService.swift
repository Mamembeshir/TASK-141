import CoreData
import Foundation

/// Local authentication service.
///
/// - AUTH-01: password validation — min 8 chars, at least 1 number.
/// - AUTH-02: hashed password verification (Keychain + SHA-256 salt).
/// - AUTH-03: lockout after N consecutive failed logins for a fixed duration.
/// - AUTH-04: biometric unlock requires a prior successful password login
///            in the current session.
/// - AUTH-05: haptic feedback — success on biometric pass, error on fail.
///
/// Callers pass in the `NSManagedObjectContext` so tests can inject
/// an in-memory store.
final class AuthService {

    static let shared = AuthService()
    private init() {}

    // MARK: - Policy

    /// Consecutive failed logins before the account locks.
    static let maxFailedAttempts: Int16 = 5

    /// How long an account stays locked after hitting `maxFailedAttempts`.
    static let lockoutDuration: TimeInterval = 15 * 60  // 15 minutes

    /// Action strings used for auth-specific audit entries.
    enum AuthAuditAction {
        static let loginFailed = "LOGIN_FAILED"
        static let deactivate  = "DEACTIVATE"
    }

    // MARK: - Session

    /// The user that last successfully authenticated with a password in this
    /// process. Biometric unlock uses this as the "prior password login" gate.
    private(set) var currentUser: User?

    // MARK: - Password validation (AUTH-01)

    /// Returns true if the password satisfies AUTH-01:
    /// at least 8 characters AND contains at least one digit.
    static func isPasswordValid(_ password: String) -> Bool {
        guard password.count >= 8 else { return false }
        return password.contains { $0.isNumber }
    }

    // MARK: - Registration

    /// Creates a new user, stores the password hash in the Keychain, and
    /// writes an audit log entry. `actorID` is the user performing the
    /// registration (typically an admin); for the very first admin account
    /// pass `nil` and the new user is used as its own actor.
    ///
    /// Throws `AuthError.passwordTooWeak` or `.usernameTaken`.
    @discardableResult
    func register(
        username: String,
        password: String,
        role: Role,
        actorID: UUID?,
        context: NSManagedObjectContext
    ) throws -> User {
        guard Self.isPasswordValid(password) else { throw AuthError.passwordTooWeak }

        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AuthError.invalidCredentials }

        // When an actorID is supplied the caller is not the bootstrap path —
        // only an admin may create other users.
        if let actorUUID = actorID {
            let actorFetch = NSFetchRequest<User>(entityName: "User")
            actorFetch.predicate = NSPredicate(format: "id == %@", actorUUID as CVarArg)
            actorFetch.fetchLimit = 1
            guard let actor = try context.fetch(actorFetch).first,
                  actor.role == Role.admin.rawValue else {
                throw AuthError.insufficientPermissions
            }
        }

        let fetch = NSFetchRequest<User>(entityName: "User")
        fetch.predicate = NSPredicate(format: "username ==[c] %@", trimmed)
        fetch.fetchLimit = 1
        if try context.fetch(fetch).first != nil {
            throw AuthError.usernameTaken
        }

        let user = User(context: context)
        user.id = UUID()
        user.username = trimmed
        user.role = role.rawValue
        user.status = UserStatus.active.rawValue
        user.failedLoginCount = 0
        user.biometricEnabled = false
        user.version = 0
        user.createdAt = Date()

        KeychainHelper.shared.storePasswordHash(for: user.id.uuidString, password: password)

        AuditService.shared.logCreate(
            actorID: actorID ?? user.id,
            entityType: "User",
            entityID: user.id,
            context: context
        )
        try context.save()
        return user
    }

    // MARK: - Login (AUTH-02 / AUTH-03)

    /// Verifies credentials. On success: resets failure count, records a
    /// LOGIN audit entry, sets `currentUser`, and saves. On failure:
    /// increments `failedLoginCount`, records LOGIN_FAILED, and — on the
    /// Nth consecutive failure — locks the account and records LOCK.
    ///
    /// Throws `.invalidCredentials`, `.accountLocked(until:)`,
    /// or `.accountDeactivated`.
    @discardableResult
    func login(
        username: String,
        password: String,
        context: NSManagedObjectContext
    ) throws -> User {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)

        let fetch = NSFetchRequest<User>(entityName: "User")
        fetch.predicate = NSPredicate(format: "username ==[c] %@", trimmed)
        fetch.fetchLimit = 1
        guard let user = try context.fetch(fetch).first else {
            throw AuthError.invalidCredentials
        }

        if user.status == UserStatus.deactivated.rawValue {
            throw AuthError.accountDeactivated
        }

        // Still within a lockout window.
        if let until = user.lockedUntil, until > Date() {
            throw AuthError.accountLocked(until: until)
        }

        // Lockout window expired — auto-unlock and let the attempt proceed.
        if user.status == UserStatus.locked.rawValue {
            user.status = UserStatus.active.rawValue
            user.lockedUntil = nil
            user.failedLoginCount = 0
            user.version += 1
            AuditService.shared.log(
                actorID: user.id,
                action: AuditAction.unlock,
                entityType: "User",
                entityID: user.id,
                context: context
            )
        }

        let ok = KeychainHelper.shared.verifyPassword(for: user.id.uuidString, password: password)

        if ok {
            user.failedLoginCount = 0
            user.lockedUntil = nil
            user.version += 1
            AuditService.shared.log(
                actorID: user.id,
                action: AuditAction.login,
                entityType: "User",
                entityID: user.id,
                context: context
            )
            try context.save()
            currentUser = user
            return user
        }

        // Failed attempt.
        user.failedLoginCount += 1
        let failed = user.failedLoginCount

        AuditService.shared.log(
            actorID: user.id,
            action: AuthAuditAction.loginFailed,
            entityType: "User",
            entityID: user.id,
            context: context
        )

        if failed >= Self.maxFailedAttempts {
            let until = Date().addingTimeInterval(Self.lockoutDuration)
            user.status = UserStatus.locked.rawValue
            user.lockedUntil = until
            user.version += 1
            AuditService.shared.log(
                actorID: user.id,
                action: AuditAction.lock,
                entityType: "User",
                entityID: user.id,
                context: context
            )
            try context.save()
            throw AuthError.accountLocked(until: until)
        }

        user.version += 1
        try context.save()
        throw AuthError.invalidCredentials
    }

    // MARK: - Logout

    func logout(context: NSManagedObjectContext) {
        if let id = currentUser?.id {
            AuditService.shared.log(
                actorID: id,
                action: AuditAction.logout,
                entityType: "User",
                entityID: id,
                context: context
            )
            try? context.save()
        }
        currentUser = nil
    }

    // MARK: - Biometric (AUTH-04 / AUTH-05)

    /// Prompts FaceID/TouchID. AUTH-04: requires a prior successful password
    /// login in the current session (`currentUser` must be non-nil), otherwise
    /// fails with `.sessionExpired`. AUTH-05: plays a success haptic on pass,
    /// error haptic on fail.
    func biometricAuth(
        reason: String = "Unlock GreenGate",
        completion: @escaping (Result<User, AuthError>) -> Void
    ) {
        guard let user = currentUser else {
            HapticHelper.error()
            completion(.failure(.sessionExpired))
            return
        }
        guard BiometricHelper.isAvailable else {
            HapticHelper.error()
            completion(.failure(.biometricNotAvailable))
            return
        }
        BiometricHelper.authenticate(reason: reason) { success, _ in
            if success {
                HapticHelper.success()
                completion(.success(user))
            } else {
                HapticHelper.error()
                completion(.failure(.biometricFailed))
            }
        }
    }

    // MARK: - Admin: lock / unlock / deactivate

    /// Admin-only: change a user's status and write an audit entry.
    /// Unlocking also resets the failure count and clears `lockedUntil`.
    func setStatus(
        _ status: UserStatus,
        for user: User,
        actorID: UUID,
        context: NSManagedObjectContext
    ) throws {
        // Enforce admin-only access at the service layer.
        let actorFetch = NSFetchRequest<User>(entityName: "User")
        actorFetch.predicate = NSPredicate(format: "id == %@", actorID as CVarArg)
        actorFetch.fetchLimit = 1
        guard let actor = try context.fetch(actorFetch).first,
              actor.role == Role.admin.rawValue else {
            throw AuthError.insufficientPermissions
        }

        let action: String
        switch status {
        case .locked:      action = AuditAction.lock
        case .active:      action = AuditAction.unlock
        case .deactivated: action = AuthAuditAction.deactivate
        }
        user.status = status.rawValue
        if status == .active {
            user.failedLoginCount = 0
            user.lockedUntil = nil
        }
        if status == .locked && user.lockedUntil == nil {
            user.lockedUntil = Date().addingTimeInterval(Self.lockoutDuration)
        }
        user.version += 1

        AuditService.shared.log(
            actorID: actorID,
            action: action,
            entityType: "User",
            entityID: user.id,
            context: context
        )
        try context.save()
    }
}
