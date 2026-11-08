@testable import ArtexMac
import XCTest

final class ToolRunPresentationTests: XCTestCase {
    func testCommandAndPlainTextRemainLiteral() {
        XCTAssertEqual(ToolRunPresentation.input(#"{"command":"echo <タグ>\nsecond"}"#), "echo <タグ>\nsecond")
        XCTAssertEqual(ToolRunPresentation.input("<script>"), "<script>")
        XCTAssertEqual(ToolRunPresentation.preview("一行目\n二行目"), "一行目")
    }

    func testLeadingBOMAndDecomposedCommandBytesArePreserved() {
        let command = "\u{FEFF}e\u{301}"
        let input = #"{"command":"\uFEFFe\u0301"}"#
        XCTAssertEqual(Array(ToolRunPresentation.input(input).utf8), Array(command.utf8))
        let structured = #"{"path":"\uFeFFe\u0301"}"#
        XCTAssertEqual(ToolRunPresentation.input(structured), structured)
    }

    func testStructuredInputAndPreview() {
        XCTAssertEqual(ToolRunPresentation.input(#"{"path":"/結果"}"#), "{\n  \"path\" : \"/結果\"\n}")
        XCTAssertEqual(ToolRunPresentation.input("42"), "42")
        let prefix = String(repeating: "語", count: 80)
        XCTAssertEqual(ToolRunPresentation.preview(prefix + "末尾"), prefix + "…")
    }
}
