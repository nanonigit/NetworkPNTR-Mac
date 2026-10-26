import XCTest
@testable import ArtexCore

final class FindingReadStateTests: XCTestCase {
    private func assertTrue(_ value: Bool,file: StaticString = #filePath,line: UInt = #line) { XCTAssertTrue(value,file:file,line:line) }
    private func assertFalse(_ value: Bool,file: StaticString = #filePath,line: UInt = #line) { XCTAssertFalse(value,file:file,line:line) }
    @MainActor private func reached(_ predicate: () -> Bool) async throws {
        for _ in 0..<10000 { if predicate() { return }; await Task.yield() }
        XCTFail("Expected controlled suspension"); throw CancellationError()
    }
    @MainActor func testReadKeepsLastGoodOnFailureAndNormalizesCancellation() async throws {
        let read = FindingReadState<String>()
        assertTrue(await read.refresh { "e\u{301} 中文 한국어" }); XCTAssertFalse(read.isStale)
        assertFalse(await read.refresh { throw BackendAPIError.status(500) }); XCTAssertEqual(read.value,"e\u{301} 中文 한국어")
        XCTAssertTrue(read.isStale); XCTAssertNotNil(read.failure)
        assertTrue(await read.refresh { "recovered" }); XCTAssertNil(read.failure)
        let cancelled = Task { withUnsafeCurrentTask{$0?.cancel()}; return await read.refresh { XCTFail("precancelled load"); return "bad" } }
        assertFalse(await cancelled.value); XCTAssertEqual(read.value,"recovered"); XCTAssertFalse(read.isLoading)
    }
    @MainActor func testInvalidatedOldReadAndItsCleanupCannotOverwriteNewRead() async throws {
        let read = FindingReadState<String>(); var held: [CheckedContinuation<String,Error>] = []
        let old = Task { await read.refresh { try await withCheckedThrowingContinuation{held.append($0)} } }
        try await reached{held.count == 1}; assertFalse(await read.refresh { XCTFail("overlap"); return "bad" })
        read.invalidate(clear:true)
        let new = Task { await read.refresh { try await withCheckedThrowingContinuation{held.append($0)} } }
        try await reached{held.count == 2}; held[0].resume(returning:"old"); assertFalse(await old.value)
        XCTAssertNil(read.value); XCTAssertTrue(read.isLoading)
        held[1].resume(returning:"new"); assertTrue(await new.value); XCTAssertEqual(read.value,"new"); XCTAssertFalse(read.isLoading)
    }
    @MainActor func testPostAwaitCancellationNeverCommitsOrLeaksRawFailure() async throws {
        let read = FindingReadState<String>(); var held: CheckedContinuation<String,Error>?
        let work = Task { await read.refresh { try await withCheckedThrowingContinuation{held=$0} } }
        try await reached{held != nil}; work.cancel(); held!.resume(returning:"never commit")
        assertFalse(await work.value); XCTAssertNil(read.value); XCTAssertFalse(read.isLoading); XCTAssertNil(read.failure)
    }
    private func page(_ page: Int64,total: Int64,size: Int) throws -> FindingPage {
        let json = "{\"items\":[],\"page\":\(page),\"page_size\":\(size),\"total\":\(total)}"
        return try BackendJSONCoding.decode(FindingPage.self,from:Data(json.utf8))
    }
    @MainActor func testPageCorrectionIsOverflowSafeAndLimitedToOneExtraRead() async throws {
        let state = FindingPageState<FindingPage>(size:20,maximum:200)
        XCTAssertTrue(state.configure(page:99,size:20)); var requests: [Int64] = []
        assertTrue(await state.refresh { page,size in requests.append(page); return try self.page(page,total:page == 99 ? 21 : 0,size:size) })
        XCTAssertEqual(requests,[99,2]); XCTAssertEqual(state.page,2); XCTAssertEqual(state.read.value?.page,2)
        assertTrue(await state.refresh { page,size in requests.append(page); return try self.page(page,total:0,size:size) })
        XCTAssertEqual(requests,[99,2,2,1]); XCTAssertEqual(state.page,1)
        XCTAssertFalse(state.configure(page:Int64.max,size:2)); XCTAssertFalse(state.configure(page:1,size:201))
        XCTAssertTrue(state.configure(page:1,size:1)); assertTrue(await state.refresh {page,size in try self.page(page,total:Int64.max,size:size)})
    }
    @MainActor func testInvalidatedPageReadCannotChangeCursorOrNewLoading() async throws {
        let state = FindingPageState<FindingPage>(size:20,maximum:200); var held: CheckedContinuation<FindingPage,Error>?
        XCTAssertTrue(state.configure(page:99,size:20))
        let old = Task { await state.refresh {_,_ in try await withCheckedThrowingContinuation{held=$0}} }
        try await reached{held != nil}; XCTAssertTrue(state.configure(page:5,size:10)); held!.resume(returning:try page(99,total:0,size:20))
        assertFalse(await old.value); XCTAssertEqual(state.page,5); XCTAssertNil(state.read.value)
        state.reset(); XCTAssertEqual(state.page,1); XCTAssertEqual(state.size,20)
    }
}
