import UIKit

enum ImageCompressor {

    static let maxLongEdgePx: CGFloat = 2048
    static let jpegQuality: CGFloat   = 0.8

    /// Compresses a UIImage to max 2048px long edge, JPEG 0.8 quality.
    /// Returns compressed JPEG data, or nil if compression fails.
    static func compress(_ image: UIImage) -> Data? {
        let resized = resize(image, maxLongEdge: maxLongEdgePx)
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    /// Loads image data from disk and compresses it.
    static func compressFile(at url: URL) -> Data? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return compress(image)
    }

    // MARK: - Private

    private static func resize(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
