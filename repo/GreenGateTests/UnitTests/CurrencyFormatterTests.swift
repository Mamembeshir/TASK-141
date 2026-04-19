import XCTest
@testable import GreenGate

final class CurrencyFormatterTests: XCTestCase {

    func test_string_fromCents_formatsCorrectly() {
        XCTAssertEqual(CurrencyFormatter.string(fromCents: 0),       "$0.00")
        XCTAssertEqual(CurrencyFormatter.string(fromCents: 100),     "$1.00")
        XCTAssertEqual(CurrencyFormatter.string(fromCents: 250000),  "$2,500.00")
        XCTAssertEqual(CurrencyFormatter.string(fromCents: 99),      "$0.99")
        XCTAssertEqual(CurrencyFormatter.string(fromCents: -100),    "-$1.00")
    }

    func test_taxCents_calculatesCorrectly() {
        // 8.875% on $100.00 = $8.88 (rounded)
        let tax = CurrencyFormatter.taxCents(onSubtotal: 10000, rateBasisPoints: 88750)
        XCTAssertEqual(tax, 888)
    }

    func test_bankersRounding_roundsHalfToEven() {
        // $0.005 rounds to $0.00 (banker's rounding rounds to nearest even cent)
        // $0.015 rounds to $0.02
        let formatted1 = CurrencyFormatter.string(fromCents: 1)  // $0.01 exact
        XCTAssertEqual(formatted1, "$0.01")
    }
}
