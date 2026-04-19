import UIKit

/// Helper for presenting UIAlertController confirmation dialogs for destructive actions.
enum ConfirmationAlertHelper {

    /// Presents a destructive confirmation alert.
    /// - Parameters:
    ///   - title:       Alert title, e.g. "Void Order"
    ///   - message:     Explanatory message.
    ///   - destructiveTitle: Title of the destructive button, e.g. "Void"
    ///   - on:          The presenting view controller.
    ///   - confirmed:   Called when the user taps the destructive button.
    static func present(
        title: String,
        message: String,
        destructiveTitle: String,
        on viewController: UIViewController,
        confirmed: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(
            title: destructiveTitle,
            style: .destructive
        ) { _ in
            confirmed()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        viewController.present(alert, animated: true)
    }

    /// Presents an action sheet (for iPad, anchored to a bar button or view).
    static func presentActionSheet(
        title: String,
        message: String?,
        destructiveTitle: String,
        on viewController: UIViewController,
        sourceView: UIView? = nil,
        sourceBarButtonItem: UIBarButtonItem? = nil,
        confirmed: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(
            title: destructiveTitle,
            style: .destructive
        ) { _ in
            confirmed()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // iPad popover source
        if let ppc = alert.popoverPresentationController {
            if let barButton = sourceBarButtonItem {
                ppc.barButtonItem = barButton
            } else if let view = sourceView {
                ppc.sourceView = view
                ppc.sourceRect = view.bounds
            } else {
                ppc.sourceView = viewController.view
                ppc.sourceRect = CGRect(x: viewController.view.bounds.midX,
                                        y: viewController.view.bounds.midY,
                                        width: 0, height: 0)
            }
        }

        viewController.present(alert, animated: true)
    }

    /// Simple information/error alert with a single OK button.
    static func presentInfo(
        title: String,
        message: String,
        on viewController: UIViewController,
        dismissed: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in dismissed?() })
        viewController.present(alert, animated: true)
    }
}
