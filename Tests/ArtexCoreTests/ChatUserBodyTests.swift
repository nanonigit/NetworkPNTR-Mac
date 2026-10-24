import Foundation
import XCTest
@testable import ArtexCore

final class ChatUserBodyTests: XCTestCase {
    func testParsingMatchesTwelveExecutedPinnedBrowserCases() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let reference = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("evidence/chat/user-body-browser-reference.json"))) as! [String: Any]
        let cases = try XCTUnwrap(reference["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 12)
        for fixture in cases {
            let name = try XCTUnwrap(fixture["name"] as? String)
            let expected = try XCTUnwrap(fixture["expected"] as? [String: Any])
            let body = ChatUserBody(rawBody: try XCTUnwrap(fixture["body"] as? String))
            XCTAssertEqual(Array(body.text.utf8), Array(try XCTUnwrap(expected["text"] as? String).utf8), name)
            let cards = try JSONDecoder().decode([ChatAttachment].self, from: JSONSerialization.data(withJSONObject: expected["attachments"] as Any))
            XCTAssertEqual(body.attachments, cards, name)
        }
    }
    func testInvalidMetadataFallsBackToLiteralBodyRatherThanInterpretingPaths() {
        for record in [
            #"{"name":"a","path":"/private/host/a","size":1}"#,
            #"{"name":"a","path":"uploads/../a","size":1}"#,
            #"{"name":"a","path":"uploads/a","size":-1}"#,
            #"{"name":"a","path":"uploads/a","size":1.5}"#,
            #"{"name":"a","path":"uploads/a","size":134217729}"#,
            #"{"name":"a","path":"uploads/a"}"#,
            #"null"#
        ] {
            let raw = #"{"text":"keep literal","attachments":["# + record + "]}"
            let body = ChatUserBody(rawBody: raw)
            XCTAssertTrue(body.text.utf8.elementsEqual(raw.utf8)); XCTAssertTrue(body.attachments.isEmpty)
        }
        for raw in [#"{"text":"keep","attachments":null}"#, #"{"attachments":{}}"#] {
            XCTAssertEqual(ChatUserBody(rawBody: raw).text, raw)
        }
    }
    func testNonStringTextAndUnknownFieldsDoNotLeakGuestAbsoluteMetadata() {
        let raw = #"{"text":{},"attachments":[{"name":"a","path":"uploads/a","size":0,"abs":"/guest/fixture/a","future":true}]}"#
        let body = ChatUserBody(rawBody: raw)
        XCTAssertEqual(body.text, ""); XCTAssertEqual(body.attachments.count, 1)
        XCTAssertEqual(body.attachments.first?.path, "uploads/a")
    }
}
