import Foundation

enum MagicBytesValidator {

    struct ValidationResult {
        let isValid: Bool
        let detectedMimeType: AttachmentMimeType?
    }

    /// Validates the magic bytes (file signature) of data against the declared MIME type.
    static func validate(data: Data, declaredMimeType: AttachmentMimeType) -> ValidationResult {
        guard let detected = detect(data: data) else {
            return ValidationResult(isValid: false, detectedMimeType: nil)
        }
        return ValidationResult(isValid: detected == declaredMimeType, detectedMimeType: detected)
    }

    /// Detects MIME type from the first few bytes of data.
    static func detect(data: Data) -> AttachmentMimeType? {
        guard data.count >= 12 else { return nil }
        let bytes = Array(data.prefix(12))

        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return .jpeg
        }

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return .png
        }

        // HEIC: ftyp box at offset 4, brand "heic", "heix", "mif1", "msf1"
        if data.count >= 12 {
            let ftypStart = data.index(data.startIndex, offsetBy: 4)
            let ftypEnd   = data.index(ftypStart, offsetBy: 4)
            let ftyp = String(data: data[ftypStart..<ftypEnd], encoding: .ascii) ?? ""
            if ftyp == "ftyp" {
                let brandStart = data.index(ftypEnd, offsetBy: 0)
                let brandEnd   = data.index(brandStart, offsetBy: 4)
                let brand = String(data: data[brandStart..<brandEnd], encoding: .ascii) ?? ""
                if ["heic", "heix", "mif1", "msf1"].contains(brand.lowercased().trimmingCharacters(in: .whitespaces)) {
                    return .heic
                }
            }
        }

        // MP4 / MOV: ftyp at offset 4
        if data.count >= 12 {
            let ftypStart = data.index(data.startIndex, offsetBy: 4)
            let ftypEnd   = data.index(ftypStart, offsetBy: 4)
            let ftyp = String(data: data[ftypStart..<ftypEnd], encoding: .ascii) ?? ""
            if ftyp == "ftyp" {
                let brandStart = data.index(ftypEnd, offsetBy: 0)
                let brandEnd   = data.index(brandStart, offsetBy: 4)
                let brand = String(data: data[brandStart..<brandEnd], encoding: .ascii) ?? ""
                let b = brand.lowercased().trimmingCharacters(in: .whitespaces)
                if ["mp42", "mp41", "isom", "avc1"].contains(b) { return .mp4 }
                if ["qt  ", "mqt "].contains(b)                  { return .mov }
            }
        }

        // PDF: %PDF
        if bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 {
            return .pdf
        }

        // MP3: ID3 or 0xFF 0xFB / 0xFF 0xF3 / 0xFF 0xF2
        if bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33 { return .mp3 }
        if bytes[0] == 0xFF && (bytes[1] == 0xFB || bytes[1] == 0xF3 || bytes[1] == 0xF2) { return .mp3 }

        // M4A: ftyp M4A
        if data.count >= 12 {
            let ftypStart = data.index(data.startIndex, offsetBy: 4)
            let ftypEnd   = data.index(ftypStart, offsetBy: 4)
            let ftyp = String(data: data[ftypStart..<ftypEnd], encoding: .ascii) ?? ""
            if ftyp == "ftyp" {
                let brandStart = ftypEnd
                let brandEnd   = data.index(brandStart, offsetBy: 4)
                let brand = String(data: data[brandStart..<brandEnd], encoding: .ascii) ?? ""
                if brand.lowercased().trimmingCharacters(in: .whitespaces) == "m4a " { return .m4a }
            }
        }

        return nil
    }
}
