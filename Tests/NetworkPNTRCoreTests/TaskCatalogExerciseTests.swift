import XCTest
@testable import NetworkPNTRCore

final class TaskCatalogExerciseTests: XCTestCase {
    @MainActor private func fixture() throws -> ChatTestTransport {
        let api = ChatTestTransport()
        let category: [String:Any] = ["id":8,"name":"T11 e\u{301} 日本語","task_count":0,"created_at":"c","updated_at":"u"]
        var renamed = category; renamed["name"] = "T11 renamed e\u{301} 日本語"
        var template: [String:Any] = ["id":12,"name":"T11 template e\u{301}","description":"Description e\u{301} \u{FEFF} interior 中文 한국어","goal":"Local contract fixture only","category_id":8,"intercept_rules":[["enabled":true,"action":"block","kind":"exact_domain","pattern":"example.invalid","note":"fixture {name} e\u{301}"]]]
        try api.enqueue(["tasks":[],"active":""]); try api.enqueue(["categories":[]]); try api.enqueue(["templates":[]])
        try api.enqueue(category,status:201); try api.enqueue(["error":"private conflict"],status:409); try api.enqueue(renamed)
        try api.enqueue(template,status:201)
        template["name"] = "T11 updated e\u{301}"; template["category_id"] = NSNull(); template["intercept_rules"] = []
        try api.enqueue(template); try api.enqueue(["templates":[template]])
        template["category_id"] = 8; try api.enqueue(template); try api.enqueue(["deleted":8])
        template["category_id"] = NSNull(); try api.enqueue(["templates":[template]])
        try api.enqueue(["error":"private missing"],status:404)
        try api.enqueue(["items":[["id":"9223372036854775806","ok":false,"error":"private"],["id":"9223372036854775805","ok":false]],"category":NSNull()])
        try api.enqueue(["deleted":12]); try api.enqueue(["categories":[]]); try api.enqueue(["templates":[]]); try api.enqueue(["tasks":[],"active":""])
        return api
    }
    @MainActor func testFiniteExerciseKeepsLiteralFieldsAndNeverStartsTask() async throws {
        let api = try fixture(); let report = try await TaskCatalogExercise.run(client:api)
        XCTAssertEqual(report.checks.count,12); XCTAssertEqual(report.categoryName,"T11 renamed e\u{301} 日本語")
        XCTAssertEqual(Data(report.templateDescription.utf8),Data("Description e\u{301} \u{FEFF} interior 中文 한국어".utf8))
        XCTAssertEqual(api.calls.count,18); XCTAssertTrue(api.replies.isEmpty)
        XCTAssertFalse(api.calls.contains { $0.path == "/api/tasks" && $0.method != "GET" || $0.path.contains("/control") || $0.path.contains("llm") })
        let clear = try XCTUnwrap(api.calls[7].body); let body = try XCTUnwrap(JSONSerialization.jsonObject(with:clear) as? [String:Any])
        XCTAssertTrue(body["category_id"] is NSNull); XCTAssertEqual((body["intercept_rules"] as? [Any])?.count,0)
    }
    @MainActor func testNonemptyInitialCatalogOrWrongConflictNeverContinues() async throws {
        for index in [0,1,2,4] {
            let api = try fixture()
            if index == 4 { api.replies[index] = .init(status:500,body:Data()) }
            else {
                let value: Any
                if index == 0 {
                    let url = try XCTUnwrap(Bundle.module.url(forResource:"task-contract",withExtension:"json",subdirectory:"Fixtures"))
                    let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]); value = try XCTUnwrap(root["task"])
                } else { value = try JSONSerialization.jsonObject(with:api.replies[index == 1 ? 3 : 6].body) }
                api.replies[index] = try ChatTestTransport.response([index == 0 ? "tasks" : index == 1 ? "categories" : "templates":[value]])
            }
            do { _ = try await TaskCatalogExercise.run(client:api); XCTFail("Invalid environment accepted") } catch {}
            XCTAssertEqual(api.calls.count,index+1)
        }
    }
    @MainActor func testReadbackUnicodeLinkageAndFinalStateCannotBeSkipped() async throws {
        for index in [6,8,9,11,13,15,16,17] {
            let api = try fixture(); api.replies[index] = .init(status:200,body:Data("{}".utf8))
            do { _ = try await TaskCatalogExercise.run(client:api); XCTFail("Incomplete exercise accepted") } catch {}
            XCTAssertEqual(api.calls.count,index+1)
        }
    }
    @MainActor func testCancellationBeforeAndDuringExerciseStopsDispatch() async throws {
        let api = try fixture(); let before = Task { try await TaskCatalogExercise.run(client:api) }; before.cancel()
        do { _ = try await before.value; XCTFail("Precancel accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(api.calls.isEmpty)
        api.handler = { call in withUnsafeCurrentTask { $0?.cancel() }; return try ChatTestTransport.response(["tasks":[],"active":""]) }
        let during = Task { try await TaskCatalogExercise.run(client:api) }
        do { _ = try await during.value; XCTFail("Postcancel accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(api.calls.count,1)
    }
    @MainActor func testValidButMismatchedPatchAndReadbackCannotPass() async throws {
        for index in [7,8,11] {
            let api = try fixture()
            var row = try XCTUnwrap(JSONSerialization.jsonObject(with:api.replies[7].body) as? [String:Any])
            if index == 7 { row["name"] = "wrong name" }
            if index == 8 { row["description"] = "Description é \u{FEFF} interior 中文 한국어" }
            if index == 11 { row["category_id"] = 8 }
            let object: Any
            if index == 7 { object = row } else { object = ["templates":[row]] }
            api.replies[index] = try ChatTestTransport.response(object)
            do { _ = try await TaskCatalogExercise.run(client:api); XCTFail("Valid mismatched receipt accepted") } catch {}
            XCTAssertEqual(api.calls.count,index+1)
        }
    }
    @MainActor func testTerminalFailureIncompleteExerciseOrBadBootCannotPass() async throws {
        let exercise = try await TaskCatalogExercise.run(client:fixture())
        let audit = GuestBootLogAudit(diagnostics:[],credentialsAbsent:true,isolationWitnessesPresent:true,formatStageObserved:true,complete:true)
        let boot = BackendPreflightReport(reachedReady:true,freshAuth:true,protectedStatus:401,cooperativeStop:true,machineStopped:true,audit:audit)
        XCTAssertTrue(TaskCatalogRunReport(stage:.complete,boot:boot,exercise:exercise,terminalSuccess:true).passed)
        XCTAssertFalse(TaskCatalogRunReport(stage:.complete,boot:boot,exercise:exercise,terminalSuccess:false).passed)
        XCTAssertFalse(TaskCatalogRunReport(stage:.shutdown,boot:boot,exercise:exercise,terminalSuccess:true).passed)
        XCTAssertFalse(TaskCatalogRunReport(stage:.complete,boot:boot,exercise:nil,terminalSuccess:true).passed)
        let partial = TaskCatalogExerciseReport(checks:[],categoryName:exercise.categoryName,templateDescription:exercise.templateDescription,templateGoal:exercise.templateGoal,rulePattern:exercise.rulePattern,ruleNote:exercise.ruleNote)
        XCTAssertFalse(TaskCatalogRunReport(stage:.complete,boot:boot,exercise:partial,terminalSuccess:true).passed)
        let failed = BackendPreflightReport(reachedReady:true,freshAuth:true,protectedStatus:401,cooperativeStop:false,machineStopped:false,audit:audit)
        XCTAssertFalse(TaskCatalogRunReport(stage:.complete,boot:failed,exercise:exercise,terminalSuccess:true).passed)
    }

}
