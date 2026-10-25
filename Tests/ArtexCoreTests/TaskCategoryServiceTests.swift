import XCTest
@testable import ArtexCore

final class TaskCategoryServiceTests: XCTestCase {
    private let big: Int64 = 9007199254740993
    private func row(_ id: Int64 = 7, name: String = "\u{FEFF}e\u{301} 中文 한국어") -> [String:Any] {
        ["id":id,"name":name,"task_count":3,"created_at":"created","updated_at":"updated"]
    }
    private func object(_ body: Data?) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(body)) as? [String:Any])
    }
    private func task(_ id: String = "7", category: Int64? = 8) throws -> [String:Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"task-contract",withExtension:"json",subdirectory:"Fixtures"))
        let root = try object(Data(contentsOf:url)); var record = try XCTUnwrap(root["task"] as? [String:Any])
        record["id"] = id; record["category_id"] = category.map { $0 as Any } ?? NSNull()
        record["category_name"] = category == nil ? NSNull() : "category"; return record
    }
    @MainActor private func rejected(_ action: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await action(); XCTFail("Accepted invalid contract",file:file,line:line) } catch {}
    }
    @MainActor func testCRUDExactWireAndLiteralLargeIdentifiers() async throws {
        let api = ChatTestTransport()
        let client = TaskCategoryService(client:api)
        // Use raw bytes for text because JSONSerialization can remove a leading BOM in string values.
        let raw = Data(#"{"id":9007199254740993,"name":"\ufeffe\u0301 中文 한국어","task_count":3,"created_at":"created","updated_at":"updated"}"#.utf8)
        api.replies = [.init(status:201,body:raw),.init(status:200,body:raw),.init(status:200,body:Data(#"{"deleted":9007199254740993}"#.utf8))]
        let name = "e\u{301} 中文 한국어"
        let created = try await client.create(name:" \u{FEFF}"+name+" \n")
        XCTAssertEqual(created.id,big); XCTAssertEqual(Data(created.name.utf8),Data(("\u{FEFF}"+name).utf8)); XCTAssertEqual(created.taskCount,3)
        XCTAssertEqual(created.createdAt,"created"); XCTAssertEqual(created.updatedAt,"updated")
        let renamed = try await client.rename(id:big,name:name); XCTAssertEqual(renamed.id,big)
        let deleted = try await client.delete(id:big); XCTAssertEqual(deleted,big)
        XCTAssertEqual(api.calls.map(\.method),["POST","PATCH","DELETE"])
        XCTAssertEqual(api.calls.map(\.path),["/api/task-categories","/api/task-categories/\(big)","/api/task-categories/\(big)"])
        XCTAssertEqual(try object(api.calls[0].body)["name"] as? String,name)
        XCTAssertEqual(Set(try object(api.calls[1].body).keys),["name"]); XCTAssertNil(api.calls[2].body)
    }
    @MainActor func testNameValidationMatchesServerBeforeWhitespaceCollapse() async throws {
        let api = ChatTestTransport()
        let client = TaskCategoryService(client:api)
        for name in ["", " \n", "\u{85}",String(repeating:"a",count:81),String(repeating:"e\u{301}",count:41),"a"+String(repeating:" ",count:80)+"b"] {
            await rejected { _ = try await client.create(name:name) }
        }
        for id: Int64 in [0,-1] {
            await rejected { _ = try await client.rename(id:id,name:"valid") }
            await rejected { _ = try await client.delete(id:id) }
        }
        XCTAssertTrue(api.calls.isEmpty)
        for name in [String(repeating:"e\u{301}",count:40),"\u{85}a\u{85}","a  b"] {
            try api.enqueue(row(),status:201); _ = try await client.create(name:name)
            XCTAssertEqual(Data((try XCTUnwrap(object(api.calls.last?.body)["name"] as? String)).utf8),Data(name.utf8))
        }
        for error in [TaskCategoryInputError.invalid, .nameLimit, .invalidBatch] {
            XCTAssertNotEqual(AppErrorMessage(error).text(language:.english),AppErrorMessage(error).text(language:.japanese))
            XCTAssertEqual(AppErrorText.text(error,language:.english),AppErrorMessage(error).text(language:.english))
        }
    }
    @MainActor func testListSchemaBoundsNullAndDuplicateIDs() async throws {
        let api = ChatTestTransport(), service = TaskCategoryService(client:api)
        try api.enqueue(["categories":[row()]]); let rows = try await service.list(); XCTAssertEqual(rows.first?.id,7)
        try api.enqueue(["categories":NSNull()]); let empty = try await service.list(); XCTAssertTrue(empty.isEmpty)
        for invalid: Any in [[:], ["categories":[row(),row()]], ["categories":[row(0)]], ["categories":[["id":7,"name":"n","task_count":-1,"created_at":"c","updated_at":"u"]]], ["categories":[["id":7,"name":"n","created_at":"c","updated_at":"u"]]]] {
            try api.enqueue(invalid); await rejected { _ = try await service.list() }
        }
        api.replies.append(.init(status:200,body:Data(repeating:32,count:4*1024*1024+1))); await rejected { _ = try await service.list() }
    }
    @MainActor func testSingleAssignmentClearAndOwnerValidation() async throws {
        let api = ChatTestTransport(), service = TaskCategoryService(client:api)
        try api.enqueue(task()); let assigned = try await service.assign(taskID:"0007",categoryID:8)
        XCTAssertEqual(assigned.id,"7"); XCTAssertEqual(assigned.categoryId,8)
        try api.enqueue(task(category:nil)); _ = try await service.assign(taskID:"7",categoryID:nil)
        XCTAssertEqual(api.calls.map(\.path),["/api/tasks/7/category","/api/tasks/7/category"])
        XCTAssertEqual(api.calls.map(\.method),["PATCH","PATCH"])
        XCTAssertTrue(try object(api.calls[1].body)["category_id"] is NSNull)
        for invalid in [try task("8"),try task(category:9),try task(category:nil)] {
            try api.enqueue(invalid); await rejected { _ = try await service.assign(taskID:"7",categoryID:8) }
        }
        let count = api.calls.count
        for id in ["../7","0","-1","9223372036854775808","７"] { await rejected { _ = try await service.assign(taskID:id,categoryID:8) } }
        await rejected { _ = try await service.assign(taskID:"7",categoryID:0) }; XCTAssertEqual(api.calls.count,count)
    }
    @MainActor func testBatchPartialAllFailedAndClearReceipts() async throws {
        let api = ChatTestTransport(), service = TaskCategoryService(client:api)
        let items: [[String:Any]] = [["id":"7","ok":true],["id":"8","ok":false,"error":"private-token /guest/path"]]
        try api.enqueue(["items":items,"category":row(big)])
        let result = try await service.assignBatch(taskIDs:["0007","7","8"],categoryID:big)
        XCTAssertEqual(result.items.map(\.id),["7","8"]); XCTAssertTrue(result.items[0].ok); XCTAssertFalse(result.items[1].ok)
        XCTAssertEqual(result.category?.id,big); XCTAssertFalse(String(describing:result).contains("private-token"))
        let wire = try object(api.calls[0].body); XCTAssertEqual(wire["task_ids"] as? [String],["7","8"]); XCTAssertEqual(wire["category_id"] as? Int64,big)
        XCTAssertEqual(api.calls[0].path,"/api/tasks/category/batch"); XCTAssertEqual(api.calls[0].method,"POST")
        try api.enqueue(["items":[["id":"7","ok":false]],"category":NSNull()]); let failed = try await service.assignBatch(taskIDs:["7"],categoryID:big)
        XCTAssertFalse(failed.items[0].ok); XCTAssertNil(failed.category)
        try api.enqueue(["items":[["id":"7","ok":true]],"category":NSNull()]); let cleared = try await service.assignBatch(taskIDs:["7"],categoryID:nil)
        XCTAssertNil(cleared.category); XCTAssertTrue(try object(api.calls.last?.body)["category_id"] is NSNull)
    }
    @MainActor func testBatchMalformedResponseInvalidInputAndExactStatuses() async throws {
        let api = ChatTestTransport(), service = TaskCategoryService(client:api)
        for bad: Any in [
            ["items":[["id":"8","ok":true]],"category":row()],
            ["items":[["id":"7","ok":true],["id":"7","ok":true]],"category":row()],
            ["items":[["id":"7","ok":true]],"category":NSNull()],
            ["items":[["id":"7","ok":true]],"category":row(8)],
            ["items":[["id":"7","ok":true]]],
            ["items":[["id":"7"]],"category":row()]
        ] { try api.enqueue(bad); await rejected { _ = try await service.assignBatch(taskIDs:["7"],categoryID:7) } }
        try api.enqueue(["items":[["id":"7","ok":true]],"category":row()]); await rejected { _ = try await service.assignBatch(taskIDs:["7"],categoryID:nil) }
        let count = api.calls.count
        for ids in [[],["0"],["7?x"],(1...101).map(String.init)] { await rejected { _ = try await service.assignBatch(taskIDs:ids,categoryID:7) } }
        await rejected { _ = try await service.assignBatch(taskIDs:["7"],categoryID:-1) }; XCTAssertEqual(api.calls.count,count)
        for status in [200,202,204,400,409,500] {
            try api.enqueue(row(),status:status); await rejected { _ = try await service.create(name:"valid") }
        }
        try api.enqueue(row(8)); await rejected { _ = try await service.rename(id:7,name:"valid") }
        try api.enqueue(["deleted":8]); await rejected { _ = try await service.delete(id:7) }
    }
    @MainActor func testCancellationBeforeAndAfterSingleDispatch() async throws {
        let api = ChatTestTransport(), service = TaskCategoryService(client:api)
        let cancelled = Task { @MainActor in try await service.create(name:"valid") }; cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Precancel accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(api.calls.isEmpty)
        api.handler = { _ in withUnsafeCurrentTask { $0?.cancel() }; return try ChatTestTransport.response(["deleted":7]) }
        let late = Task { @MainActor in try await service.delete(id:7) }
        do { _ = try await late.value; XCTFail("Late cancellation accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(api.calls.count,1)
    }
}
