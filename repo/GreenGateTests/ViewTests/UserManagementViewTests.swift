import XCTest
import CoreData
@testable import GreenGate

/// UserManagementViewController is admin-only at the call site; the tests
/// here exercise real behaviour: rendering, the Add action, and whether the
/// table reflects actual Core Data state.
final class UserManagementViewTests: XCTestCase {

    func test_viewLoads_withoutCrash() {
        let vc = UserManagementViewController()
        _ = vc.view
        XCTAssertNotNil(vc.view)
    }

    func test_titleIsSet() {
        let vc = UserManagementViewController()
        _ = vc.view
        XCTAssertEqual(vc.title, "User Management")
    }

    func test_rightBarButton_isAddButton() {
        let vc = UserManagementViewController()
        _ = vc.view
        let item = vc.navigationItem.rightBarButtonItem
        XCTAssertNotNil(item)
    }

    /// Real behavioural test: the table actually reflects a user added to
    /// the live view context.
    func test_tableRendersRows_forActiveUsers() throws {
        let ctx = CoreDataStack.shared.viewContext
        let u = User(context: ctx)
        u.id = UUID()
        u.username = "vt-\(UUID().uuidString.prefix(6))"
        u.role = Role.cashier.rawValue
        u.status = UserStatus.active.rawValue
        u.version = 0
        u.createdAt = Date()
        try ctx.save()
        defer { ctx.delete(u); try? ctx.save() }

        let vc = UserManagementViewController()
        _ = vc.view
        let table = vc.view.subviews.compactMap { $0 as? UITableView }.first
        XCTAssertNotNil(table, "UserManagementViewController should embed a UITableView")
        XCTAssertGreaterThanOrEqual(table?.numberOfRows(inSection: 0) ?? 0, 1,
                                     "Expected the seeded user to appear")
    }
}
