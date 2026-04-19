import UIKit
import AVFoundation

enum ThumbnailGenerator {

    static let thumbnailSize = CGSize(width: 160, height: 160)

    /// Generates a thumbnail from an image or video file.
    /// Returns the URL of the written thumbnail JPEG, or nil on failure.
    @discardableResult
    static func generate(from fileURL: URL, outputURL: URL) -> URL? {
        let ext = fileURL.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "heic"].contains(ext) {
            return generateImageThumbnail(fileURL: fileURL, outputURL: outputURL)
        } else if ["mp4", "mov"].contains(ext) {
            return generateVideoThumbnail(fileURL: fileURL, outputURL: outputURL)
        }
        return nil
    }

    // MARK: - Image

    private static func generateImageThumbnail(fileURL: URL, outputURL: URL) -> URL? {
        guard let image = UIImage(contentsOfFile: fileURL.path) else { return nil }
        let thumbnail = resizeToFit(image: image, size: thumbnailSize)
        guard let data = thumbnail.jpegData(compressionQuality: 0.7) else { return nil }
        do {
            try data.write(to: outputURL)
            return outputURL
        } catch {
            return nil
        }
    }

    // MARK: - Video

    private static func generateVideoThumbnail(fileURL: URL, outputURL: URL) -> URL? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            let image = UIImage(cgImage: cgImage)
            let thumbnail = resizeToFit(image: image, size: thumbnailSize)
            guard let data = thumbnail.jpegData(compressionQuality: 0.7) else { return nil }
            try data.write(to: outputURL)
            return outputURL
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private static func resizeToFit(image: UIImage, size: CGSize) -> UIImage {
        let aspect = image.size.width / image.size.height
        let targetAspect = size.width / size.height

        var drawRect = CGRect(origin: .zero, size: size)
        if aspect > targetAspect {
            let h = size.width / aspect
            drawRect.origin.y = (size.height - h) / 2
            drawRect.size.height = h
        } else {
            let w = size.height * aspect
            drawRect.origin.x = (size.width - w) / 2
            drawRect.size.width = w
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: drawRect)
        }
    }
}
