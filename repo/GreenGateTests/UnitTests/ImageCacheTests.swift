import XCTest
import UIKit
@testable import GreenGate

/// Verifies that ImageCache stores/retrieves images and purges on memory warning.
final class ImageCacheTests: XCTestCase {

    var cache: ImageCache!

    override func setUp() {
        super.setUp()
        cache = ImageCache()   // fresh instance per test; avoids shared-state cross-contamination
    }

    override func tearDown() {
        cache.removeAll()
        cache = nil
        super.tearDown()
    }

    // MARK: - Basic store / retrieve

    func test_setAndGet_returnsStoredImage() {
        let image = makeImage(color: .red)
        cache.set(image, forKey: "red")
        XCTAssertNotNil(cache.image(forKey: "red"))
    }

    func test_get_missingKey_returnsNil() {
        XCTAssertNil(cache.image(forKey: "no-such-key"))
    }

    func test_remove_evictsEntry() {
        let image = makeImage(color: .blue)
        cache.set(image, forKey: "blue")
        cache.remove(forKey: "blue")
        XCTAssertNil(cache.image(forKey: "blue"))
    }

    func test_removeAll_evictsEverything() {
        cache.set(makeImage(color: .green), forKey: "a")
        cache.set(makeImage(color: .yellow), forKey: "b")
        cache.removeAll()
        XCTAssertNil(cache.image(forKey: "a"))
        XCTAssertNil(cache.image(forKey: "b"))
    }

    // MARK: - Memory warning clears cache

    func test_memoryWarningNotification_clearsCache() {
        cache.set(makeImage(color: .purple), forKey: "x")
        cache.set(makeImage(color: .orange), forKey: "y")

        NotificationCenter.default.post(name: .didReceiveMemoryWarning, object: nil)

        XCTAssertNil(cache.image(forKey: "x"), "Cache should be empty after memory warning")
        XCTAssertNil(cache.image(forKey: "y"), "Cache should be empty after memory warning")
    }

    func test_memoryWarningNotification_emptyCache_doesNotCrash() {
        // Must not throw or crash on an already-empty cache.
        XCTAssertNoThrow(
            NotificationCenter.default.post(name: .didReceiveMemoryWarning, object: nil)
        )
    }

    func test_cacheRemainsUsable_afterMemoryWarning() {
        NotificationCenter.default.post(name: .didReceiveMemoryWarning, object: nil)
        let image = makeImage(color: .cyan)
        cache.set(image, forKey: "post-warning")
        XCTAssertNotNil(cache.image(forKey: "post-warning"),
                        "Cache should accept new entries after a memory warning")
    }

    // MARK: - Helpers

    private func makeImage(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}
