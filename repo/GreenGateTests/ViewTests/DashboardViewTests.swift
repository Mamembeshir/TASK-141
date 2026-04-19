import XCTest
@testable import GreenGate

final class DashboardViewTests: XCTestCase {

    func test_viewControllerLoads_withoutCrash() {
        let vc = DashboardViewController()
        _ = vc.view  // triggers viewDidLoad
        XCTAssertNotNil(vc.view)
    }

    func test_titleIsSet() {
        let vc = DashboardViewController()
        _ = vc.view
        XCTAssertEqual(vc.title, "Dashboard")
    }

    func test_backgroundColorIsSet() {
        let vc = DashboardViewController()
        _ = vc.view
        XCTAssertNotNil(vc.view.backgroundColor)
    }
}
