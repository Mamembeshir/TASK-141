import XCTest
@testable import GreenGate

final class SHA256HelperTests: XCTestCase {

    func test_hash_string_isConsistent() {
        let h1 = SHA256Helper.hash("GreenGate")
        let h2 = SHA256Helper.hash("GreenGate")
        XCTAssertEqual(h1, h2)
    }

    func test_hash_string_isDifferentForDifferentInputs() {
        let h1 = SHA256Helper.hash("password1")
        let h2 = SHA256Helper.hash("password2")
        XCTAssertNotEqual(h1, h2)
    }

    func test_hash_string_isLowercaseHex() {
        let h = SHA256Helper.hash("test")
        XCTAssertTrue(h.allSatisfy { $0.isHexDigit })
        XCTAssertEqual(h.count, 64)
    }

    func test_hash_data_matchesStringHash() {
        let str = "hello"
        let h1 = SHA256Helper.hash(str)
        let h2 = SHA256Helper.hash(Data(str.utf8))
        XCTAssertEqual(h1, h2)
    }
}
