import XCTest
import CoreData
@testable import GreenGate

/// View tests for the Admin module: AuditLog and ImportExport.
final class AdminViewTests: XCTestCase {

    func test_auditLog_loads_andEmbedsTableAndFilter() {
        let vc = AuditLogViewController()
        _ = vc.view
        XCTAssertEqual(vc.title, "Audit Log")
        let segs = vc.view.subviews.compactMap { $0 as? UISegmentedControl }
        XCTAssertEqual(segs.first?.numberOfSegments, 5,
                       "Filter should expose All + 4 entity-type segments")
        XCTAssertNotNil(vc.navigationItem.searchController,
                        "Audit log must support search per the spec")
    }

    func test_auditLog_rendersExistingRows() throws {
        let ctx = CoreDataStack.shared.viewContext
        let id = UUID()
        AuditService.shared.logCreate(actorID: UUID(), entityType: "AdminViewTest",
                                       entityID: id, context: ctx)
        try ctx.save()
        defer {
            let fr = NSFetchRequest<AuditLog>(entityName: "AuditLog")
            fr.predicate = NSPredicate(format: "entityID == %@", id as CVarArg)
            for log in (try? ctx.fetch(fr)) ?? [] { ctx.delete(log) }
            try? ctx.save()
        }
        let vc = AuditLogViewController()
        _ = vc.view
        let table = vc.view.subviews.compactMap { $0 as? UITableView }.first
        XCTAssertNotNil(table)
        XCTAssertGreaterThanOrEqual(table?.numberOfRows(inSection: 0) ?? 0, 1)
    }

    func test_importExport_loads_andHasImportAndExportSections() {
        let vc = ImportExportViewController()
        _ = vc.view
        let table = vc.view.subviews.compactMap { $0 as? UITableView }.first
        XCTAssertNotNil(table)
        XCTAssertGreaterThanOrEqual(table?.numberOfSections ?? 0, 2,
                                     "Should show at least Import and Export sections")
    }
}
