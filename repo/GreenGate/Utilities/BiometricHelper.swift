import LocalAuthentication

enum BiometricHelper {

    enum BiometricType {
        case faceID, touchID, none
    }

    /// Returns the available biometric type on this device.
    static var availableType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID:  return .faceID
        case .touchID: return .touchID
        default:       return .none
        }
    }

    /// Returns true if any biometric authentication is available.
    static var isAvailable: Bool { availableType != .none }

    /// Prompts biometric authentication with the given reason.
    /// Calls completion on the main queue with success/error.
    static func authenticate(reason: String, completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            DispatchQueue.main.async { completion(false, error) }
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        ) { success, evalError in
            DispatchQueue.main.async { completion(success, evalError) }
        }
    }
}
