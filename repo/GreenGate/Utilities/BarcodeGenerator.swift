import UIKit
import CoreImage

enum BarcodeGenerator {

    /// Generates a QR code image from the given string payload.
    /// Returns nil if generation fails.
    static func qrCode(from string: String, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")   // Medium error correction

        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size.width  / ciImage.extent.width
        let scaleY = size.height / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Generates a Code128 barcode image.
    static func barcode128(from string: String, size: CGSize = CGSize(width: 300, height: 80)) -> UIImage? {
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")

        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size.width  / ciImage.extent.width
        let scaleY = size.height / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
