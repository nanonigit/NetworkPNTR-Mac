import XCTest
@testable import ArtexMac

final class LLMRecordPresentationTests: XCTestCase {
    func testFormatsNestedJSONWithoutChangingLexemes() {
        let raw = #" {"z": [1,{"日本語":"a\"b\\c"}, []],"n":9007199254740993,"n":1e+08,"empty":{}} "#
        XCTAssertEqual(LLMRecordPresentation.jsonBody(raw), #"""
        {
          "z": [
            1,
            {
              "日本語": "a\"b\\c"
            },
            []
          ],
          "n": 9007199254740993,
          "n": 1e+08,
          "empty": {}
        }
        """#)
    }

    func testKeepsSourceWhenIndentationWouldExceedDisplayLimit() {
        let values = String(repeating: "0,", count: 20_000) + "0"
        let input = String(repeating: "[", count: 120) + values + String(repeating: "]", count: 120)
        XCTAssertEqual(LLMRecordPresentation.jsonBody(input), input)
    }

    func testLeavesNonJSONAndEmptyValuesIntact() {
        for input in ["data: {\"x\":1}\n\n", "{broken", "[1,]", "", "\u{FEFF}{}"] {
            XCTAssertEqual(LLMRecordPresentation.jsonBody(input), input)
        }
        XCTAssertNil(LLMRecordPresentation.jsonBody(nil))
        XCTAssertEqual(LLMRecordPresentation.jsonBody("  true "), "true")
    }
}
