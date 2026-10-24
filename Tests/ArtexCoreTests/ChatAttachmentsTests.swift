import Foundation
import XCTest
@testable import ArtexCore

final class ChatAttachmentsTests: XCTestCase {
    func testMetadataDecodeDropsAbsolutePathAndEncodesOnlyGuestRelativeFields() throws {
        let wire = Data(#"{"attachments":[{"name":"日本語 +?.txt","path":"uploads/日本語 +?.txt","size":0,"abs":"/private/guest/sessions/conv-7/uploads/日本語 +?.txt"}]}"#.utf8)
        let attachments = try JSONDecoder().decode(ChatUploadResponse.self, from: wire).attachments
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments[0].name, "日本語 +?.txt")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attachments[0])) as! [String: Any]
        XCTAssertEqual(Set(encoded.keys), ["name","path","size"])
        XCTAssertEqual(encoded["path"] as? String, "uploads/日本語 +?.txt")
    }
    func testCanonicalEquivalentGuestFilenamesRemainDistinctAndRequireExactPathBytes() throws {
        let nfc = "\u{E9}.txt", nfd = "e\u{301}.txt"
        let first = try ChatAttachment(name: nfc, path: "uploads/" + nfc, size: 1)
        let second = try ChatAttachment(name: nfd, path: "uploads/" + nfd, size: 1)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first.id,second.id]).count, 2)
        XCTAssertThrowsError(try ChatAttachment(name: nfc, path: "uploads/" + nfd, size: 1))
        let wire = try JSONSerialization.data(withJSONObject: ["attachments":[first.json,second.json]])
        let decoded = try JSONDecoder().decode(ChatUploadResponse.self, from: wire).attachments
        XCTAssertEqual(decoded.count, 2)
        XCTAssertTrue(decoded[0].name.utf8.elementsEqual(nfc.utf8))
        XCTAssertTrue(decoded[1].name.utf8.elementsEqual(nfd.utf8))
    }
    func testInvalidMetadataAndMissingEmptyOrDuplicateEnvelopeFail() throws {
        for name in ["", ".", "..", "a/b", "a\\b", "x\n", "x\0", String(repeating: "a", count: 256)] {
            XCTAssertThrowsError(try ChatAttachment(name: name, path: "uploads/" + name, size: 0))
        }
        for path in ["/Users/private/file", "../file", "uploads/../file", "sessions/conv-8/uploads/file", "uploads/other"] {
            XCTAssertThrowsError(try ChatAttachment(name: "file", path: path, size: 0))
        }
        for size: Int64 in [-1,128 * 1024 * 1024 + 1] { XCTAssertThrowsError(try ChatAttachment(name: "file", path: "uploads/file", size: size)) }
        _ = try ChatAttachment(name: "file", path: "uploads/file", size: 128 * 1024 * 1024)
        for json in [#"{}"#, #"{"attachments":null}"#, #"{"attachments":[]}"#,
                     #"{"attachments":[{"name":"a","path":"uploads/a","size":0},{"name":"a","path":"uploads/a","size":0}]}"#,
                     #"{"attachments":[{"name":"a","path":"uploads/a","size":-1}]}"#,
                     #"{"attachments":[{"name":"a","path":"uploads/a","size":0.5}]}"#,
                     #"{"attachments":[{"name":"a","path":"uploads/a"}]}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ChatUploadResponse.self, from: Data(json.utf8)))
        }
    }
    @MainActor func testAttachmentOnlySendUsesThreeFieldMetadataAndRequiresAcknowledgement() async throws {
        let api = ChatTestTransport(), service = ChatService(client: api)
        let attachment = try ChatAttachment(name: "file", path: "uploads/file", size: 1)
        try api.enqueue(["status":"accepted"],status:202)
        try await service.send(id: 7, message: "", attachments: [attachment])
        let call = try XCTUnwrap(api.calls.last)
        XCTAssertEqual(call.path, "/api/conversations/7/messages")
        let object = try JSONSerialization.jsonObject(with: XCTUnwrap(call.body)) as! [String:Any]
        XCTAssertEqual(object["message"] as? String, "")
        let metadata = try XCTUnwrap((object["attachments"] as? [[String:Any]])?.first)
        XCTAssertEqual(Set(metadata.keys), ["name","path","size"])
        try api.enqueue(["status":"not-accepted"])
        do { try await service.send(id: 7, message: "", attachments: [attachment]); XCTFail("Invalid acknowledgement") } catch { }
        let count = api.calls.count
        do { try await service.send(id: 7, message: " \n", attachments: []); XCTFail("Empty send") } catch { }
        XCTAssertEqual(api.calls.count, count)
    }
}
