import UIKit

/// In-memory image cache backed by `NSCache`.
/// Automatically purges all entries when the system posts a memory warning
/// (via `Notification.Name.didReceiveMemoryWarning` from `AppDelegate`).
final class ImageCache {

    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: .didReceiveMemoryWarning,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    // MARK: - Memory warning

    @objc private func handleMemoryWarning() {
        cache.removeAllObjects()
    }
}
