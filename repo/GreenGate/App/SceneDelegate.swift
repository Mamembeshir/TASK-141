import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window

        window.rootViewController = buildRootViewController(for: windowScene.traitCollection)
        window.makeKeyAndVisible()

        // Override point: apply global tint from design system
        window.tintColor = UIColor(named: "GreenPrimary")
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {
        ParkedTicketService.shared.startTimer()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        ParkedTicketService.shared.stopTimer()
    }
    func sceneWillEnterForeground(_ scene: UIScene) {}

    func sceneDidEnterBackground(_ scene: UIScene) {
        try? CoreDataStack.shared.saveViewContext()
    }

    // MARK: - Root VC Construction

    private func buildRootViewController(for traits: UITraitCollection) -> UIViewController {
        guard AuthService.shared.currentUser != nil else {
            return makeLoginViewController(for: traits)
        }
        return SceneRouter.buildRoot(
            forRole: AuthService.shared.currentUser?.role,
            traits: traits
        )
    }

    private func makeLoginViewController(for traits: UITraitCollection) -> UIViewController {
        let login = LoginViewController()
        login.onLoginSuccess = { [weak self] user in
            guard let self, let window = self.window else { return }
            let currentTraits = window.windowScene?.traitCollection ?? traits
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                window.rootViewController = SceneRouter.buildRoot(
                    forRole: user.role,
                    traits: currentTraits
                )
            }
        }
        return login
    }

}

// MARK: - SceneRouter

/// Role + idiom → root view controller. Extracted from `SceneDelegate` so
/// that the routing logic is directly unit-testable without needing a live
/// `UIWindowScene`. TKT-07 Gate-Attendant gating lives here.
enum SceneRouter {

    /// Tab order used by the iPhone root. Exposed so tests can assert the
    /// exact set of tabs and their ordering.
    static let iPhoneTabTitles = ["Dashboard", "Products", "POS", "Tickets", "Properties", "Learning"]

    static func buildRoot(forRole role: String?, traits: UITraitCollection) -> UIViewController {
        // TKT-07: Gate Attendant is restricted to the scanner only — no tab
        // bar, no other modules.
        if role == Role.gateAttendant.rawValue {
            return UINavigationController(rootViewController: TicketScannerViewController())
        }
        let parsedRole = role.flatMap { Role(rawValue: $0) }
        if traits.userInterfaceIdiom == .pad {
            return buildIPadRoot(role: parsedRole)
        } else {
            return buildIPhoneRoot(role: parsedRole)
        }
    }

    static func buildIPhoneRoot(role: Role?) -> UITabBarController {
        let allowed = role?.allowedModules ?? []
        var vcs: [UINavigationController] = []
        if allowed.contains(.dashboard) {
            vcs.append(makeNav(DashboardViewController(),    title: "Dashboard",  image: "house",      tag: 0))
        }
        if allowed.contains(.products) {
            vcs.append(makeNav(ProductListViewController(),  title: "Products",   image: "leaf",       tag: 1))
        }
        if allowed.contains(.pos) {
            vcs.append(makeNav(POSViewController(),          title: "POS",        image: "cart",       tag: 2))
        }
        if allowed.contains(.tickets) {
            vcs.append(makeNav(EventListViewController(),    title: "Tickets",    image: "ticket",     tag: 3))
        }
        if allowed.contains(.properties) {
            vcs.append(makeNav(PropertyListViewController(),        title: "Properties", image: "building.2",  tag: 4))
        }
        if allowed.contains(.learningContent) {
            vcs.append(makeNav(LearningContentListViewController(), title: "Learning",   image: "book.fill",   tag: 5))
        }
        let tab = UITabBarController()
        tab.viewControllers = vcs
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        tab.tabBar.standardAppearance = appearance
        tab.tabBar.scrollEdgeAppearance = appearance
        return tab
    }

    static func buildIPadRoot(role: Role?) -> UISplitViewController {
        let split = UISplitViewController(style: .doubleColumn)
        split.preferredDisplayMode = .oneBesideSecondary
        split.preferredSplitBehavior = .tile
        let sidebar = SidebarViewController(role: role)
        split.setViewController(UINavigationController(rootViewController: sidebar), for: .primary)
        let detail = DashboardViewController()
        split.setViewController(UINavigationController(rootViewController: detail), for: .secondary)
        return split
    }

    private static func makeNav(_ vc: UIViewController, title: String,
                                image: String, tag: Int) -> UINavigationController {
        vc.title = title
        let nav = UINavigationController(rootViewController: vc)
        nav.tabBarItem = UITabBarItem(
            title: title, image: UIImage(systemName: image), tag: tag
        )
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }
}

// MARK: - Trait Collection Changes

extension SceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: UICoordinateSpace,
        interfaceOrientation: UIInterfaceOrientation,
        traitCollection: UITraitCollection
    ) {
        // Adaptive layout handled by individual VCs via traitCollectionDidChange
    }
}
