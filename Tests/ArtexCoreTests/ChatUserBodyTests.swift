import Foundation
import XCTest
@testable import ArtexCore

final class ChatUserBodyTests: XCTestCase {
    func testParsingMatchesTwelveExecutedPinnedBrowserCases() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        struct Expected: Decodable { let text: String; let attachments: [ChatAttachment] }
        struct Fixture: Decodable { let name: String; let body: String; let expected: Expected }
        struct Reference: Decodable { let cases: [Fixture] }
        let data = try Data(contentsOf: root.appendingPathComponent("evidence/chat/user-body-browser-reference.json"))
        let cases = try JSONDecoder().decode(Reference.self, from: data).cases
        XCTAssertEqual(cases.count, 12)
        XCTAssertEqual(cases.first { $0.name == "bom_prefix" }?.body.utf8.first, 239)
        for fixture in cases {
            let body = ChatUserBody(rawBody: fixture.body)
            XCTAssertEqual(Array(body.text.utf8), Array(fixture.expected.text.utf8), fixture.name)
            XCTAssertEqual(body.attachments, fixture.expected.attachments, fixture.name)
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
