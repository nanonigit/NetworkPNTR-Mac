import XCTest
import ArtexCore
@testable import ArtexMac

final class TrafficFilterDraftsTests: XCTestCase {
    func testIndependentTicketsApplyOnlyTheirOwnFields() throws {
        var drafts = TrafficFilterDrafts()
        drafts.edit(.host, text:" host ")
        let host = drafts.ticket(.host)
        drafts.edit(.keyword, text:" keyword ")
        let keyword = drafts.ticket(.keyword)
        var first = try XCTUnwrap(drafts.proposal(for:host, query:TrafficQuery()))
        first = try XCTUnwrap(first.drafts.proposal(for:keyword, query:first.query))
        XCTAssertEqual(first.query.host,"host"); XCTAssertEqual(first.query.keyword,"keyword")
        XCTAssertEqual(first.drafts.text(.host)," host ")
    }
    func testStaleAndRetypedTicketsAreRejected() {
        var drafts = TrafficFilterDrafts(); drafts.edit(.body,text:"a")
        let old = drafts.ticket(.body)
        drafts.edit(.body,text:"b"); drafts.edit(.body,text:"a")
        XCTAssertNil(drafts.proposal(for:old,query:TrafficQuery()))
        let current = drafts.ticket(.body); drafts.edit(.body,text:"a")
        XCTAssertNotNil(drafts.proposal(for:current,query:TrafficQuery()))
    }
    func testPresentationReplacementRejectsIdenticalOldInput() {
        var old = TrafficFilterDrafts(); old.edit(.path,text:"/a")
        var fresh = TrafficFilterDrafts(); fresh.edit(.path,text:"/a")
        XCTAssertNil(fresh.proposal(for:old.ticket(.path),query:TrafficQuery()))
    }
    func testTrimUsesECMAScriptAndPreservesPacketSearchBytes() throws {
        var drafts = TrafficFilterDrafts()
        let raw = "\u{FEFF} e\u{301} 中文 한국어\u{0085}\u{FEFF} "
        drafts.edit(.path,text:raw)
        let proposal = try XCTUnwrap(drafts.proposal(for:drafts.ticket(.path),query:TrafficQuery()))
        XCTAssertEqual(Data(proposal.query.path.utf8),Data("e\u{301} 中文 한국어\u{0085}".utf8))
        XCTAssertEqual(Data(proposal.drafts.text(.path).utf8),Data(raw.utf8))
    }
    func testCanonicalEquivalentInputsRemainDistinct() throws {
        var drafts = TrafficFilterDrafts(); drafts.edit(.host,text:"é")
        let old = drafts.ticket(.host)
        drafts.edit(.host,text:"e\u{301}")
        XCTAssertNil(drafts.proposal(for:old,query:TrafficQuery()))
        let result = try XCTUnwrap(drafts.proposal(for:drafts.ticket(.host),query:TrafficQuery()))
        XCTAssertEqual(Data(result.query.host.utf8),Data("e\u{301}".utf8))
    }
    func testNormalizedNoOpPreservesHistoryPage() throws {
        var drafts = TrafficFilterDrafts(); drafts.edit(.host,text:"host")
        let first = try XCTUnwrap(drafts.proposal(for:drafts.ticket(.host),query:TrafficQuery()))
        drafts = first.drafts; var query = first.query; query.page = 7
        drafts.edit(.host,text:" \u{FEFF}host ")
        let second = try XCTUnwrap(drafts.proposal(for:drafts.ticket(.host),query:query))
        XCTAssertFalse(second.changed); XCTAssertEqual(second.query.page,7)
        drafts.edit(.host,text:"other")
        XCTAssertEqual(drafts.proposal(for:drafts.ticket(.host),query:query)?.query.page,0)
    }
    func testProposalDoesNotApplyUntilCallerAdoptsAcceptedCopy() throws {
        var drafts = TrafficFilterDrafts(); drafts.edit(.keyword,text:"q")
        let ticket = drafts.ticket(.keyword)
        let rejected = try XCTUnwrap(drafts.proposal(for:ticket,query:TrafficQuery()))
        XCTAssertTrue(rejected.changed)
        XCTAssertTrue(try XCTUnwrap(drafts.proposal(for:ticket,query:TrafficQuery())).changed)
        XCTAssertFalse(try XCTUnwrap(rejected.drafts.proposal(for:ticket,query:rejected.query)).changed)
    }
    func testSizeLoweringMatchesSignedLinux64Decimal() throws {
        for (raw,expected) in [("",nil),("+001",Int64(1)),("-0",0),("-1",nil),("0x10",nil),("1.5",nil),("1e3",nil),("１２",nil),("1_0",nil),("9223372036854775807",Int64.max),("9223372036854775808",nil),("--1",nil)] {
            var drafts = TrafficFilterDrafts(); drafts.edit(.responseMinimum,text:raw)
            let result = try XCTUnwrap(drafts.proposal(for:drafts.ticket(.responseMinimum),query:TrafficQuery()))
            XCTAssertEqual(result.query.responseMinimum,expected,"raw: \(raw)")
        }
    }
    func testNumericTextChangeResetsPageDespiteEqualNumericValue() throws {
        var drafts = TrafficFilterDrafts(); drafts.edit(.responseMaximum,text:"1")
        let first = try XCTUnwrap(drafts.proposal(for:drafts.ticket(.responseMaximum),query:TrafficQuery()))
        drafts = first.drafts; var query = first.query; query.page = 3
        drafts.edit(.responseMaximum,text:"01")
        let second = try XCTUnwrap(drafts.proposal(for:drafts.ticket(.responseMaximum),query:query))
        XCTAssertTrue(second.changed); XCTAssertEqual(second.query.responseMaximum,1); XCTAssertEqual(second.query.page,0)
    }
    func testInvertedRangeAndShortBodyAreNotDiscarded() throws {
        var drafts = TrafficFilterDrafts(); var query = TrafficQuery()
        for (field,text) in [(TrafficTextField.responseMinimum,"10"),(.responseMaximum,"2"),(.body,"a")] {
            drafts.edit(field,text:text)
            let next = try XCTUnwrap(drafts.proposal(for:drafts.ticket(field),query:query))
            drafts = next.drafts; query = next.query
        }
        XCTAssertEqual(query.responseMinimum,10); XCTAssertEqual(query.responseMaximum,2); XCTAssertEqual(query.body,"a")
    }
    func testAdvancedResetInvalidatesOnlyAdvancedTicketsAndRetainsPendingHost() throws {
        var drafts = TrafficFilterDrafts(); drafts.edit(.host,text:"pending host"); drafts.edit(.body,text:"pending body")
        let host = drafts.ticket(.host), body = drafts.ticket(.body)
        var query = TrafficQuery(); query.page = 4; query.method = .get; query.status = .clientError
        query.host = "applied host"; query.keyword = "q"; query.body = "old"; query.path = "/old"; query.responseMaximum = 2
        let reset = drafts.resetAdvanced(query:query)
        XCTAssertEqual(reset.query.page,0); XCTAssertEqual(reset.query.host,"applied host"); XCTAssertEqual(reset.query.keyword,"q")
        XCTAssertEqual(reset.query.method,.get); XCTAssertNil(reset.query.status)
        XCTAssertEqual(reset.query.body,""); XCTAssertEqual(reset.query.path,""); XCTAssertNil(reset.query.responseMaximum)
        XCTAssertEqual(reset.drafts.text(.body),"")
        XCTAssertNil(reset.drafts.proposal(for:body,query:reset.query))
        XCTAssertNotNil(reset.drafts.proposal(for:host,query:reset.query))
    }
    func testEmptyAdvancedResetDoesNotResetHistoryButCancelsPendingDraft() {
        var drafts = TrafficFilterDrafts(); drafts.edit(.body,text:"pending")
        let old = drafts.ticket(.body); var query = TrafficQuery(); query.page = 4
        let reset = drafts.resetAdvanced(query:query)
        XCTAssertFalse(reset.changed); XCTAssertEqual(reset.query.page,4)
        XCTAssertNil(reset.drafts.proposal(for:old,query:reset.query))
    }
    func testImmediateControlsPreserveTextAndResetOnlyOnChange() throws {
        var query = TrafficQuery(); query.page = 6; query.host = "applied"
        XCTAssertEqual(TrafficFilterControl.method(nil).applying(to:query)?.page,6)
        query = try XCTUnwrap(TrafficFilterControl.method(.post).applying(to:query))
        XCTAssertEqual(query.page,0); XCTAssertEqual(query.host,"applied"); XCTAssertEqual(query.method,.post)
        query.page = 6
        XCTAssertEqual(TrafficFilterControl.status(.clientError).applying(to:query)?.page,0)
        query.status = .exact(404)
        XCTAssertEqual(TrafficFilterControl.status(.exact(404)).applying(to:query)?.page,6)
        XCTAssertEqual(TrafficFilterControl.status(nil).applying(to:query)?.page,0)
        for size in [25,50,100,200] { XCTAssertEqual(TrafficFilterControl.size(size).applying(to:query)?.size,size) }
        for size in [0,1,500,Int.max] { XCTAssertNil(TrafficFilterControl.size(size).applying(to:query)) }
    }
    func testSortTogglesSameColumnAndStartsNewColumnDescending() throws {
        var query = TrafficQuery(); query.page = 6
        query = try XCTUnwrap(TrafficFilterControl.sort(.timestamp).applying(to:query))
        XCTAssertEqual(query.order,.ascending); XCTAssertEqual(query.page,0)
        query = try XCTUnwrap(TrafficFilterControl.sort(.timestamp).applying(to:query))
        XCTAssertEqual(query.order,.descending)
        query = try XCTUnwrap(TrafficFilterControl.sort(.status).applying(to:query))
        XCTAssertEqual(query.sort,.status); XCTAssertEqual(query.order,.descending)
        query = try XCTUnwrap(TrafficFilterControl.sort(.responseLength).applying(to:query))
        XCTAssertEqual(query.sort,.responseLength); XCTAssertEqual(query.order,.descending)
    }
}
