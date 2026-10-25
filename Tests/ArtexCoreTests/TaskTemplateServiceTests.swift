import Foundation
import XCTest
@testable import ArtexCore

final class TaskTemplateServiceTests: XCTestCase {
    private func draft() -> TaskTemplateDraft {
        var value = TaskTemplateDraft(); value.name = " preset "; value.description = " literal e\u{301}中\u{FEFF}inside "; value.goal = " goal 한국어 "
        value.interceptRules = [.init(enabled:false,action:.allow,kind:.cidr,pattern:" 10.0.0.0/8 ",note:" literal "),.init(enabled:true,action:.block,kind:.exactDomain,pattern:" \u{FEFF}",note:"")]
        return value
    }
    private func record(_ id: Int64 = 7) -> Data {
        Data(("{\"id\":\(id),\"name\":\"\\uFEFFname\",\"description\":\"\\uFEFFe\\u0301中\",\"goal\":\"goal\",\"category_id\":null,\"intercept_rules\":[]}").utf8)
    }
    func testPayloadMatchesFiveBrowserFieldsAndServerLimits() throws {
        let object = try JSONSerialization.jsonObject(with:draft().encoded()) as! [String:Any]
        XCTAssertEqual(Set(object.keys),["name","description","goal","category_id","intercept_rules"])
        XCTAssertEqual(object["name"] as? String,"preset"); XCTAssertTrue(object["category_id"] is NSNull)
        let rules = object["intercept_rules"] as! [[String:Any]]
        XCTAssertEqual(rules.count,1); XCTAssertEqual(rules[0]["pattern"] as? String,"10.0.0.0/8"); XCTAssertEqual(rules[0]["note"] as? String," literal "); XCTAssertEqual(rules[0]["enabled"] as? Bool,false)
        for key in [\TaskTemplateDraft.name,\.description,\.goal] {
            var invalid = draft(); invalid[keyPath:key] = " \n"; XCTAssertThrowsError(try invalid.encoded())
        }
        var value = draft(); value.name = String(repeating:"🧭",count:120); value.description = String(repeating:"界",count:16000); value.goal = "g"; XCTAssertNoThrow(try value.encoded())
        value.name += "x"; XCTAssertThrowsError(try value.encoded())
        value = draft(); value.goal = String(repeating:"x",count:16001); XCTAssertThrowsError(try value.encoded())
        value = draft(); value.categoryId = 0; XCTAssertThrowsError(try value.encoded())
        value = draft(); value.interceptRules[0].note = String(repeating:"x",count:512*1024); XCTAssertThrowsError(try value.encoded())
    }
    @MainActor func testCreatePatchDeleteAndRawResponsesAreExact() async throws {
        let api = ChatTestTransport(), service = TaskTemplateService(client:api)
        api.replies.append(.init(status:201,body:record(9_007_199_254_740_993)))
        let created = try await service.create(draft()); XCTAssertEqual(created.id,9_007_199_254_740_993)
        XCTAssertTrue(created.name.utf8.elementsEqual("\u{FEFF}name".utf8)); XCTAssertTrue(created.description.utf8.elementsEqual("\u{FEFF}e\u{301}中".utf8))
        api.replies.append(.init(status:200,body:record()))
        let updated = try await service.update(id:7,draft:draft()); XCTAssertEqual(updated.id,7)
        try api.enqueue(["deleted":7]); let deleted = try await service.delete(id:7); XCTAssertEqual(deleted,7)
        XCTAssertEqual(api.calls.map(\.method),["POST","PATCH","DELETE"])
        XCTAssertEqual(api.calls.map(\.path),["/api/task-templates","/api/task-templates/7","/api/task-templates/7"])
        XCTAssertNotNil(api.calls[1].body); XCTAssertNil(api.calls[2].body)
        try api.enqueue(["templates":NSNull()]); let empty = try await service.list(); XCTAssertTrue(empty.isEmpty)
    }
    @MainActor func testWrongOwnersStatusesAndBoundsCannotConfirmMutation() async throws {
        let api = ChatTestTransport(), service = TaskTemplateService(client:api)
        for response in [BackendHTTPResponse(status:200,body:record(8)),.init(status:202,body:record()),.init(status:200,body:Data(repeating:32,count:4*1024*1024+1)),.init(status:200,body:Data("{}".utf8))] {
            api.replies.append(response)
            do { _ = try await service.update(id:7,draft:draft()); XCTFail("Invalid mutation confirmed") } catch { }
        }
        try api.enqueue(["deleted":8]); do { _ = try await service.delete(id:7); XCTFail("Wrong deletion owner") } catch { }
        try api.enqueue(["error":"private server text"],status:409)
        do { _ = try await service.create(draft()); XCTFail("Conflict accepted") } catch { XCTAssertFalse(error.localizedDescription.contains("private server text")) }
        let calls = api.calls.count
        for id: Int64 in [0,-1] {
            do { _ = try await service.delete(id:id); XCTFail("Invalid ID") } catch { }
        }
        XCTAssertEqual(api.calls.count,calls)
    }
    @MainActor func testPreAndPostDispatchCancellationAndReadContract() async throws {
        let api = ChatTestTransport(), service = TaskTemplateService(client:api)
        let cancelled = Task { @MainActor in try await service.create(self.draft()) }; cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Precancel accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(api.calls.isEmpty)
        try api.enqueue(["templates":[]]); let list = try await service.list(); XCTAssertTrue(list.isEmpty)
        XCTAssertEqual(api.calls.last?.path,"/api/task-templates")
        let raw = TemplateCancellationAPI(response:.init(status:201,body:record()))
        let late = Task { @MainActor in try await TaskTemplateService(client:raw).create(self.draft()) }
        do { _ = try await late.value; XCTFail("Late cancellation accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(raw.calls,1)
        XCTAssertNotEqual(AppErrorMessage(TaskTemplateInputError.invalid).text(language:.english),AppErrorMessage(TaskTemplateInputError.invalid).text(language:.japanese))
    }
}

@MainActor private final class TemplateCancellationAPI: BackendJSONTransport {
    let response: BackendHTTPResponse
    var calls = 0
    init(response: BackendHTTPResponse) { self.response = response }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        calls += 1; withUnsafeCurrentTask { $0?.cancel() }; return response
    }
}
