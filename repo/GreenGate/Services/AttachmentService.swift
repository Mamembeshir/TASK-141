import CoreData
import Foundation
import UIKit

/// Attachment ingestion pipeline (ATT-01..07):
/// magic-byte validation → image compression (2048 px JPEG 0.8) → SHA-256
/// checksum + dedup → thumbnail generation → optional licensing/copyright
/// metadata. Files land in Application Support/Attachments/{parent}/{id}/.
final class AttachmentService {

    static let shared = AttachmentService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext
    private let repo: AttachmentRepository

    init(context: NSManagedObjectContext) {
        self.context = context
        self.repo = AttachmentRepository(context: context)
    }

    struct UploadInput {
        let sourceURL: URL
        let declaredMime: AttachmentMimeType
        let parentType: AttachmentParentType
        let parentID: UUID
        let licensing: String?
        let copyright: String?
    }

    /// Full ingestion. Returns the persisted Attachment.
    /// `uploadedBy` must be the authenticated user initiating the upload.
    @discardableResult
    func upload(_ input: UploadInput, uploadedBy: User) throws -> Attachment {
        AppConfiguration.createDirectoriesIfNeeded()

        let rawData = try Data(contentsOf: input.sourceURL)

        // ATT-01 — magic bytes must match the declared MIME.
        let validation = MagicBytesValidator.validate(data: rawData, declaredMimeType: input.declaredMime)
        guard validation.isValid else { throw AttachmentError.magicBytesMismatch }

        // ATT-02 — compress images; transcode videos to 720p MP4.
        var outputData = rawData
        var isCompressed = false
        if input.declaredMime.isImage, let image = UIImage(data: rawData),
           let compressed = ImageCompressor.compress(image) {
            outputData = compressed
            isCompressed = true
        } else if input.declaredMime.isVideo {
            let tmp = FileManager.default.temporaryDirectory
            let srcURL = tmp.appendingPathComponent(UUID().uuidString + ".src")
            let dstURL = tmp.appendingPathComponent(UUID().uuidString + ".mp4")
            try rawData.write(to: srcURL, options: .atomic)
            defer {
                try? FileManager.default.removeItem(at: srcURL)
                try? FileManager.default.removeItem(at: dstURL)
            }
            let sem = DispatchSemaphore(value: 0)
            VideoTranscoder.transcode(inputURL: srcURL, outputURL: dstURL,
                                      completionQueue: .global()) { _, _ in sem.signal() }
            sem.wait()
            if let transcoded = try? Data(contentsOf: dstURL), !transcoded.isEmpty {
                outputData = transcoded
                isCompressed = true
            }
        }

        // ATT-04 — SHA-256 dedup against the same parent.
        let checksum = SHA256Helper.hash(outputData)
        if let existing = try repo.fetchByChecksum(checksum,
                                                    parentType: input.parentType,
                                                    parentID: input.parentID) {
            _ = existing
            throw AttachmentError.duplicateAttachment
        }

        // Write to disk.
        let attachmentID = UUID()
        let fileName = "\(attachmentID.uuidString).\(input.declaredMime.fileExtension)"
        let relPath  = "Attachments/\(input.parentType.rawValue)/\(input.parentID.uuidString)/\(fileName)"
        let fullURL  = AppConfiguration.applicationSupportDirectory.appendingPathComponent(relPath)
        try FileManager.default.createDirectory(
            at: fullURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try outputData.write(to: fullURL, options: .atomic)

        // ATT-07 — thumbnail for images/videos.
        var thumbRel: String?
        if input.declaredMime.isImage || input.declaredMime.isVideo {
            let thumbName = "\(attachmentID.uuidString).thumb.jpg"
            let thumbRelPath = "Thumbnails/\(thumbName)"
            let thumbURL = AppConfiguration.applicationSupportDirectory.appendingPathComponent(thumbRelPath)
            if ThumbnailGenerator.generate(from: fullURL, outputURL: thumbURL) != nil {
                thumbRel = thumbRelPath
            }
        }

        // Persist.
        let att = Attachment(context: context)
        att.id = attachmentID
        att.parentType = input.parentType.rawValue
        att.parentID = input.parentID
        att.fileName = fileName
        att.filePath = relPath
        att.fileSizeBytes = Int64(outputData.count)
        att.mimeType = input.declaredMime.rawValue
        att.checksumSHA256 = checksum
        att.thumbnailPath = thumbRel
        att.isCompressed = isCompressed
        att.licensingInfo = input.licensing
        att.copyrightInfo = input.copyright
        att.createdAt = Date()
        att.uploadedBy = uploadedBy

        AuditService.shared.logCreate(
            actorID: uploadedBy.id,
            entityType: "Attachment", entityID: att.id, context: context
        )
        try context.save()
        return att
    }

    /// Returns the absolute disk URL for an attachment's primary file.
    func url(for attachment: Attachment) -> URL {
        AppConfiguration.applicationSupportDirectory
            .appendingPathComponent(attachment.filePath)
    }
}
