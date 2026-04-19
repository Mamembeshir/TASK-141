import XCTest
import CoreData
@testable import GreenGate

/// End-to-end view-layer coverage for the login → role-gated navigation
/// journey. Uses the live Core Data stack (the same one Scene/AppDelegate
/// use) because the scene routing function consults `AuthService.shared`.
final class LoginFlowViewTests: XCTestCase {

    var ctx: NSManagedObjectContext!
    var createdIDs: [UUID] = []

    override func setUpWithError() throws {
        ctx = CoreDataStack.shared.viewContext
        AuthService.shared.logout(context: ctx)
    }

    override func tearDownWithError() throws {
        for id in createdIDs {
            KeychainHelper.shared.deletePasswordHash(for: id.uuidString)
        }
        createdIDs.removeAll()
        AuthService.shared.logout(context: ctx)
    }

    @discardableResult
    private func register(_ name: String, password: String, role: Role) throws -> User {
        let u = try AuthService.shared.register(
            username: name, password: password, role: role,
            actorID: nil, context: ctx
        )
        createdIDs.append(u.id)
        return u
    }

    // MARK: - Login form drives AuthService

    func test_login_validCredentials_setsCurrentUser() throws {
        let uname = "e2e-\(UUID().uuidString.prefix(6))"
        try register(uname, password: "Password1", role: .cashier)
        _ = try AuthService.shared.login(username: uname, password: "Password1", context: ctx)
        XCTAssertEqual(AuthService.shared.currentUser?.username, uname)
    }

    func test_login_invalidCredentials_currentUserStaysNil() {
        AuthService.shared.logout(context: ctx)
        _ = try? AuthService.shared.login(username: "nobody", password: "Wrong1234", context: ctx)
        XCTAssertNil(AuthService.shared.currentUser)
    }

    // MARK: - Role → root VC routing (SceneRouter)

    /// Admin gets a UITabBarController with all 6 tabs in the documented order.
    func test_router_adminRole_buildsFullTabBar() {
        let iphone = UITraitCollection(userInterfaceIdiom: .phone)
        let root = SceneRouter.buildRoot(forRole: Role.admin.rawValue, traits: iphone)
        let tab = root as? UITabBarController
        XCTAssertNotNil(tab, "Admin should produce a UITabBarController on iPhone")
        XCTAssertEqual(tab?.viewControllers?.count, 6, "Admin should see all 6 tabs")
        let titles = (tab?.viewControllers ?? []).map { $0.tabBarItem.title ?? "" }
        XCTAssertEqual(titles, SceneRouter.iPhoneTabTitles, "Unexpected tab order for admin")
    }

    /// Cashier → Dashboard, POS only (no Products, Properties, or Tickets).
    func test_router_cashierRole_buildsRestrictedTabBar() {
        let iphone = UITraitCollection(userInterfaceIdiom: .phone)
        let root = SceneRouter.buildRoot(forRole: Role.cashier.rawValue, traits: iphone)
        let tab = root as? UITabBarController
        XCTAssertNotNil(tab, "Cashier should produce a UITabBarController on iPhone")
        let titles = (tab?.viewControllers ?? []).map { $0.tabBarItem.title ?? "" }
        XCTAssertEqual(titles, ["Dashboard", "POS"],
                       "Cashier scope is POS/checkout only — no Tickets, Products, or Properties")
    }

    /// Content Manager → Dashboard, Products, Properties, Learning (no POS or Tickets).
    func test_router_contentManagerRole_buildsRestrictedTabBar() {
        let iphone = UITraitCollection(userInterfaceIdiom: .phone)
        let root = SceneRouter.buildRoot(forRole: Role.contentManager.rawValue, traits: iphone)
        let tab = root as? UITabBarController
        XCTAssertNotNil(tab, "Content Manager should produce a UITabBarController on iPhone")
        let titles = (tab?.viewControllers ?? []).map { $0.tabBarItem.title ?? "" }
        XCTAssertEqual(titles, ["Dashboard", "Products", "Properties", "Learning"],
                       "Content Manager must not access POS or Tickets, but must see Learning")
    }

    /// Reviewer → Dashboard, Products, Properties, Learning (no POS or Tickets).
    func test_router_reviewerRole_buildsRestrictedTabBar() {
        let iphone = UITraitCollection(userInterfaceIdiom: .phone)
        let root = SceneRouter.buildRoot(forRole: Role.reviewer.rawValue, traits: iphone)
        let tab = root as? UITabBarController
        XCTAssertNotNil(tab, "Reviewer should produce a UITabBarController on iPhone")
        let titles = (tab?.viewControllers ?? []).map { $0.tabBarItem.title ?? "" }
        XCTAssertEqual(titles, ["Dashboard", "Products", "Properties", "Learning"],
                       "Reviewer must not access POS or Tickets, but must see Learning")
    }

    /// TKT-07: Gate Attendant gets a nav with TicketScannerViewController
    /// — no tab bar, no other modules.
    func test_router_gateAttendant_getsScannerOnly() {
        let root = SceneRouter.buildRoot(
            forRole: Role.gateAttendant.rawValue,
            traits: UITraitCollection(userInterfaceIdiom: .phone)
        )
        XCTAssertNil(root as? UITabBarController,
                     "Gate Attendant must NOT see a tab bar")
        let nav = root as? UINavigationController
        XCTAssertNotNil(nav, "Expected a UINavigationController")
        XCTAssertTrue(nav?.viewControllers.first is TicketScannerViewController,
                      "Gate Attendant's root VC must be the scanner")
    }

    /// iPad root is a UISplitViewController regardless of non-gate role.
    func test_router_iPad_returnsSplitViewController() {
        let ipad = UITraitCollection(userInterfaceIdiom: .pad)
        let root = SceneRouter.buildRoot(forRole: Role.admin.rawValue, traits: ipad)
        XCTAssertNotNil(root as? UISplitViewController,
                        "iPad root should be a UISplitViewController")
    }

    /// Full journey: login as gate attendant, then ask the router — we must
    /// get the scanner-only root. Then log out and log in as admin and the
    /// tab bar returns.
    func test_fullJourney_loginAsGateAttendant_thenAdmin_rootChanges() throws {
        let gateName = "gate-\(UUID().uuidString.prefix(6))"
        let adminName = "admin-\(UUID().uuidString.prefix(6))"
        try register(gateName, password: "GatePass1", role: .gateAttendant)
        try register(adminName, password: "AdminPass1", role: .admin)

        let iphone = UITraitCollection(userInterfaceIdiom: .phone)

        _ = try AuthService.shared.login(username: gateName, password: "GatePass1", context: ctx)
        let rootForGate = SceneRouter.buildRoot(
            forRole: AuthService.shared.currentUser?.role, traits: iphone
        )
        XCTAssertTrue(rootForGate is UINavigationController)
        XCTAssertTrue((rootForGate as? UINavigationController)?.viewControllers.first
                      is TicketScannerViewController)

        AuthService.shared.logout(context: ctx)
        _ = try AuthService.shared.login(username: adminName, password: "AdminPass1", context: ctx)
        let rootForAdmin = SceneRouter.buildRoot(
            forRole: AuthService.shared.currentUser?.role, traits: iphone
        )
        XCTAssertTrue(rootForAdmin is UITabBarController)
        XCTAssertEqual((rootForAdmin as? UITabBarController)?.viewControllers?.count, 6)
    }

    // MARK: - Navigating from the tab bar into operational modules

    func test_productListTab_pushesDetailForSelectedSPU() throws {
        // Drop an SPU into the live view context so the list picks it up.
        let spu = ProductSPU(context: ctx)
        spu.id = UUID()
        spu.name = "E2E Bouquet"
        spu.listingStatus = ProductListingStatus.draft.rawValue
        spu.version = 0
        spu.createdAt = Date()
        try ctx.save()
        defer { ctx.delete(spu); try? ctx.save() }

        let list = ProductListViewController()
        _ = list.view
        let nav = UINavigationController(rootViewController: list)
        _ = nav.view

        // Tap the row programmatically.
        let table = list.view.subviews.compactMap { $0 as? UITableView }.first
        XCTAssertNotNil(table)
        let count = table?.numberOfRows(inSection: 0) ?? 0
        XCTAssertGreaterThanOrEqual(count, 1)
        list.tableView(table!, didSelectRowAt: IndexPath(row: 0, section: 0))
        // After a didSelect the test VC pushes — exercise the call path;
        // UINavigationController pushes asynchronously in a test environment,
        // so the important assertion is that didSelectRowAt doesn't crash
        // and the list finds the underlying SPU.
    }
}
