import XCTest
import CoreData
@testable import GreenGate

/// Real-filesystem tests for CleanupService. Writes fake attachment files
/// into a sandboxed temp directory and swaps `Application Support` via
/// `HOME` override? We can't easily redirect Application Support, so these
/// tests invoke `cleanOrphans` against the real Application Support
/// directory, using distinctly-named files to avoid collision with app
/// data.
final class CleanupServiceTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var service: CleanupService!
    var temporaryFiles: [URL] = []

    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "GreenGate")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "store")
        container.loadPersistentStores { _, err in XCTAssertNil(err); exp.fulfill() }
        waitForExpectations(timeout: 5)
        context = container.viewContext
        service = CleanupService(context: context)

        let fm = FileManager.default
        let dir = attachmentRoot()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        let fm = FileManager.default
        for url in temporaryFiles { try? fm.removeItem(at: url) }
        temporaryFiles.removeAll()
        service = nil
        context = nil
        container = nil
    }

    private func attachmentRoot() -> URL {
        AppConfiguration.applicationSupportDirectory
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("cleanup-tests", isDirectory: true)
    }

    private func writeFake(name: String, ageDays: Int) throws -> URL {
        let url = attachmentRoot().appendingPathComponent(name)
        try Data("test".utf8).write(to: url)
        let modified = Calendar.current.date(byAdding: .day, value: -ageDays, to: Date())!
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        temporaryFiles.append(url)
        return url
    }

    func test_cleanOrphans_removesOldUntrackedFiles() throws {
        let oldFile = try writeFake(name: "old-\(UUID().uuidString).bin", ageDays: 10)
        let report = try service.cleanOrphans()
        XCTAssertGreaterThanOrEqual(report.removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
    }

    func test_cleanOrphans_keepsYoungFiles() throws {
        let recent = try writeFake(name: "recent-\(UUID().uuidString).bin", ageDays: 2)
        _ = try service.cleanOrphans()
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path),
                      "Files under the 7-day threshold must be kept")
    }

    func test_cleanOrphans_keepsTrackedFiles() throws {
        let fileName = "tracked-\(UUID().uuidString).bin"
        let rel = "Attachments/cleanup-tests/\(fileName)"
        let url = AppConfiguration.applicationSupportDirectory.appendingPathComponent(rel)
        try Data("test".utf8).write(to: url)
        let modified = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        try FileManager.default.setAttributes([.modificationDate: modified],
                                              ofItemAtPath: url.path)
        temporaryFiles.append(url)

        // Create a Core Data Attachment referring to this file.
        let att = Attachment(context: context)
        att.id = UUID()
        att.parentType = AttachmentParentType.product.rawValue
        att.parentID = UUID()
        att.fileName = fileName
        att.filePath = rel
        att.fileSizeBytes = 4
        att.mimeType = AttachmentMimeType.jpeg.rawValue
        att.checksumSHA256 = "abc"
        att.isCompressed = false
        att.createdAt = Date()
        try context.save()

        _ = try service.cleanOrphans()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Files referenced by an Attachment row must be kept even when old")
    }
}
