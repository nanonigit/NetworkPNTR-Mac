import Foundation
import XCTest
@testable import NetworkPNTRCore
@testable import NetworkPNTRMac

final class EvidenceTextPreviewTests: XCTestCase {
    private let marker="[二进制正文，12 字节；请下载查看]"
    private let literal="\u{FEFF}e\u{301} 日本語 中文 한국어\u{FEFF}"
    private func page(_ content: String,offset: Int64=0,next: Int64=4,total: Int64=12,binary: Bool=false) throws -> FindingEvidencePreview {
        try BackendJSONCoding.decode(FindingEvidencePreview.self,from:JSONSerialization.data(withJSONObject:["content":content,"offset":offset,"next_offset":next,"total":total,"truncated":next<total,"binary":binary]))
    }
    func testTypedBinaryHidesOnlyOwnedPlaceholderFromDisplayPreservingRawPage() throws {
        let preview=EvidenceTextPreview(try page(marker,binary:true))
        XCTAssertEqual(preview.textContent,"");XCTAssertEqual(Data(preview.content.utf8),Data(marker.utf8))
        XCTAssertTrue(preview.binary);XCTAssertFalse(preview.hasMore);XCTAssertEqual(preview.nextOffset,4);XCTAssertEqual(preview.total,12)
    }
    func testOrdinaryTextWithTheSameMarkerAndUnicodeIsNeverRewritten() throws {
        let value=literal+marker
        let preview=EvidenceTextPreview(try page(value,next:12))
        XCTAssertEqual(Data(preview.textContent.utf8),Data(value.utf8));XCTAssertEqual(Data(preview.content.utf8),Data(value.utf8))
        XCTAssertFalse(preview.binary);XCTAssertFalse(preview.hasMore)
    }
    func testLaterBinaryPageRetainsEarlierLiteralTextAndRawCumulativeContent() throws {
        var preview=EvidenceTextPreview(try page(literal))
        try preview.append(page(marker,offset:4,next:8,binary:true))
        XCTAssertEqual(Data(preview.textContent.utf8),Data(literal.utf8));XCTAssertEqual(Data(preview.content.utf8),Data((literal+marker).utf8))
        XCTAssertTrue(preview.binary);XCTAssertFalse(preview.hasMore);XCTAssertEqual(preview.nextOffset,8)
    }
    func testRejectedAppendCannotChangeRawOrDisplayContent() throws {
        for invalid in [try page(marker,offset:3,next:8,binary:true),try page(marker,offset:4,next:8,total:16,binary:true)] {
            var preview=EvidenceTextPreview(try page(literal))
            XCTAssertThrowsError(try preview.append(invalid))
            XCTAssertEqual(Data(preview.textContent.utf8),Data(literal.utf8));XCTAssertEqual(Data(preview.content.utf8),Data(literal.utf8))
            XCTAssertFalse(preview.binary);XCTAssertTrue(preview.hasMore);XCTAssertEqual(preview.nextOffset,4);XCTAssertEqual(preview.total,12)
        }
    }
}
