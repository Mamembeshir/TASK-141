import XCTest
@testable import GreenGate

final class MaskingHelperTests: XCTestCase {

    func test_maskPhone_showsLastFour() {
        XCTAssertEqual(MaskingHelper.maskPhone("2125551234"), "***-***-1234")
        XCTAssertEqual(MaskingHelper.maskPhone("(212) 555-1234"), "***-***-1234")
        XCTAssertEqual(MaskingHelper.maskPhone(""), "***-***-****")
    }

    func test_maskEmail_showsDomainOnly() {
        XCTAssertEqual(MaskingHelper.maskEmail("john@example.com"), "***@example.com")
        XCTAssertEqual(MaskingHelper.maskEmail("a@b.co"), "***@b.co")
    }

    func test_maskSSN_showsLastFour() {
        XCTAssertEqual(MaskingHelper.maskSSN("123-45-6789"), "***-**-6789")
        XCTAssertEqual(MaskingHelper.maskSSN("123456789"),   "***-**-6789")
    }

    func test_maskCardNumber_showsLastFour() {
        XCTAssertEqual(MaskingHelper.maskCardNumber("4111111111111111"), "**** **** **** 1111")
    }
}
