import XCTest
@testable import NetworkPNTRCore

final class AssetDSLSuggestionsTests: XCTestCase {
    func testOffersPinnedFieldOperatorAndLogicGroups() {
        func labels(_ text: String) -> [String] {
            AssetDSLSuggestions.items(in: text, at: text.endIndex).map(\.label)
        }

        XCTAssertEqual(labels("").count, 19)
        XCTAssertEqual(labels("do"), ["domain"])
        XCTAssertEqual(labels("DOMAIN"), ["domain=", "domain==", "domain!="])
        XCTAssertEqual(labels("port"), ["port==", "port!=", "port>", "port>=", "port<", "port<="])
        XCTAssertEqual(labels("method"), ["method==", "method!="])
        XCTAssertEqual(labels("task_id"), ["task_id=="])
        XCTAssertEqual(labels("domain=fixture"), [])
        XCTAssertEqual(labels("domain=fixture "), ["AND", "OR"])
        XCTAssertEqual(labels("domain=fixture o"), ["OR"])
        XCTAssertEqual(labels("domain=fixture OR ro"), ["root_domain"])
    }

    func testInsertionPreservesUnicodePrefixAndSuffix() throws {
        let text = #"page_title="日本語" AND dom status_code>=400"#
        let caret = try XCTUnwrap(text.range(of: "dom")).upperBound
        let suggestion = try XCTUnwrap(AssetDSLSuggestions.items(in: text, at: caret).first)
        let result = AssetDSLSuggestions.apply(suggestion, to: text)
        XCTAssertEqual(result.text, #"page_title="日本語" AND domain status_code>=400"#)
        XCTAssertEqual(String(result.text[result.caret...]), " status_code>=400")
    }
}
