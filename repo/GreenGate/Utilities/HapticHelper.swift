import UIKit

enum HapticHelper {

    /// Plays success haptic — used for successful scan, completed action.
    static func success() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.prepare()
        gen.impactOccurred()
    }

    /// Plays error haptic — used for failed scan, duplicate, validation error.
    static func error() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.error)
    }

    /// Plays light selection tap — used for stepper taps, toggle changes.
    static func selection() {
        let gen = UISelectionFeedbackGenerator()
        gen.prepare()
        gen.selectionChanged()
    }

    /// Plays warning haptic — used for approaching limits, attention needed.
    static func warning() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.warning)
    }
}
