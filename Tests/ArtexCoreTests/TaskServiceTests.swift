import XCTest
@testable import ArtexCore

final class TaskServiceTests:XCTestCase {
    private func task(_ id:String="9007199254740993") throws -> [String:Any] {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"task-contract",withExtension:"json",subdirectory:"Fixtures"))
        let root=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        XCTAssertEqual(root["baseline"] as? String,"e75ae371ad777ffd1eecdd28d2781a6519b05591")
        var value=try XCTUnwrap(root["task"] as? [String:Any]);value["id"]=id;return value
    }
    private func object(_ data:Data?) throws -> [String:Any] {try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(data)) as? [String:Any])}
    @MainActor func testListAndDetailPreserveCompleteRecordAndLargeIDs() async throws {
        let api=ChatTestTransport();let service=TaskService(client:api);let item=try task()
        try api.enqueue(["tasks":[item],"active":item["id"]!]);let list=try await service.list()
        let record=try XCTUnwrap(list.tasks.first)
        XCTAssertEqual(record.id,"9007199254740993");XCTAssertEqual(record.explorationId,9_007_199_254_740_993)
        XCTAssertEqual(record.tokens.inputTokens,9_007_199_254_740_993);XCTAssertEqual(record.findings.high,2)
        XCTAssertEqual(record.name,"literal 中文 한국어");XCTAssertEqual(list.activeID,record.id);XCTAssertNil(record.companyIds)
        try api.enqueue(item);let detail=try await service.detail(id:record.id)
        XCTAssertEqual(detail.goal,"fixture goal");XCTAssertEqual(detail.description,"fixture description {name}")
        XCTAssertEqual(api.calls.map(\.path),["/api/tasks","/api/tasks/9007199254740993"])
        try api.enqueue(["tasks":NSNull(),"active":""]);let empty=try await service.list();XCTAssertTrue(empty.tasks.isEmpty);XCTAssertNil(empty.activeID)
    }
    @MainActor func testCreateSendsAllOptionsAndDoesNotActivateOrRetry() async throws {
        let api=ChatTestTransport();let service=TaskService(client:api)
        var draft=TaskCreateDraft();draft.name="  literal 中文 한국어  ";draft.description=" desc ";draft.goal=" goal "
        draft.categoryId=7;draft.llmProfileIds=[9,8];draft.sourceTaskIds=["0002","3"];draft.companyIds=[5,5,4]
        draft.timeoutSeconds=120;draft.planHeartbeatSeconds=600;draft.seedFirstIntent=true;draft.coverageEnabled=false
        draft.interceptRules=[.init(enabled:true,action:.allow,kind:.exactDomain,pattern:" example.invalid ",note:"literal"),.init(enabled:false,action:.block,kind:.fuzzyUrl,pattern:" ",note:"")]
        try api.enqueue(task("7"),status:201);let result=try await service.create(draft);XCTAssertEqual(result.id,"7")
        XCTAssertEqual(api.calls.count,1);XCTAssertEqual(api.calls[0].method,"POST");XCTAssertEqual(api.calls[0].path,"/api/tasks")
        let body=try object(api.calls[0].body)
        XCTAssertEqual(Set(body.keys),Set(["name","category_id","description","goal","llm_profile_ids","source_task_ids","company_ids","timeout_seconds","plan_heartbeat_seconds","seed_first_intent","coverage_enabled","intercept_rules"]))
        XCTAssertEqual(body["name"] as? String,"literal 中文 한국어");XCTAssertEqual(body["description"] as? String,"desc");XCTAssertEqual(body["goal"] as? String,"goal")
        XCTAssertEqual(body["category_id"] as? Int,7);XCTAssertEqual(body["llm_profile_ids"] as? [Int],[9,8]);XCTAssertEqual(body["source_task_ids"] as? [String],["2","3"])
        XCTAssertEqual(body["company_ids"] as? [Int],[5,4]);XCTAssertEqual(body["timeout_seconds"] as? Int,120);XCTAssertEqual(body["plan_heartbeat_seconds"] as? Int,600)
        XCTAssertEqual(body["seed_first_intent"] as? Bool,true);XCTAssertEqual(body["coverage_enabled"] as? Bool,false)
        let rules=try XCTUnwrap(body["intercept_rules"] as? [[String:Any]]);XCTAssertEqual(rules.count,1);XCTAssertEqual(rules[0]["pattern"] as? String,"example.invalid");XCTAssertEqual(rules[0]["action"] as? String,"allow")
        var defaults=TaskCreateDraft();defaults.description="d";defaults.goal="g";let defaultBody=try object(defaults.encoded())
        XCTAssertTrue(defaultBody["category_id"] is NSNull);XCTAssertEqual(defaultBody["coverage_enabled"] as? Bool,true);XCTAssertEqual(defaultBody["seed_first_intent"] as? Bool,false)
    }
    @MainActor func testMetadataTriStateAndScalarLimits() async throws {
        let api=ChatTestTransport();let service=TaskService(client:api)
        try api.enqueue(task("7"));_ = try await service.update(id:"0007",patch:.init(pinned:false))
        let pin=try object(api.calls[0].body);XCTAssertEqual(Set(pin.keys),["pinned"]);XCTAssertEqual(pin["pinned"] as? Bool,false);XCTAssertEqual(api.calls[0].path,"/api/tasks/7")
        let name=String(repeating:"e\u{301}",count:100)
        try api.enqueue(task("7"));_ = try await service.update(id:"7",patch:.init(name:" "+name+" "))
        XCTAssertEqual(try object(api.calls[1].body)["name"] as? String,name)
        for patch in [TaskMetadataPatch(),.init(name:" "),.init(name:name+"x")] {
            do {_ = try await service.update(id:"7",patch:patch);XCTFail("Invalid metadata accepted")} catch {}
        }
        XCTAssertEqual(api.calls.count,2)
    }
    @MainActor func testControlAndPartialBatchKeepOwnerAndDoNotExposeErrorBodies() async throws {
        let api=ChatTestTransport();let service=TaskService(client:api)
        try api.enqueue(["id":"7","paused":true,"queued":false,"status":"paused"])
        let paused=try await service.control(id:"7",action:.pause);XCTAssertTrue(paused.paused)
        try api.enqueue(["items":[["id":"7","ok":true,"status":"queued","queued":true],["id":"8","ok":false,"error":"private-secret"]]])
        let results=try await service.controlBatch(ids:["0007","7","8"],action:.resume)
        XCTAssertEqual(results.map(\.id),["7","8"]);XCTAssertTrue(results[0].queued);XCTAssertFalse(results[1].ok)
        XCTAssertFalse(String(describing:results).contains("private-secret"))
        let body=try object(api.calls[1].body);XCTAssertEqual(body["task_ids"] as? [String],["7","8"]);XCTAssertEqual(body["action"] as? String,"resume")
        XCTAssertEqual(api.calls.map(\.path),["/api/tasks/7/control","/api/tasks/control/batch"])
    }
    @MainActor func testConfirmedDeletionRetainsCountsAndWarningPresenceWithoutRawWarning() async throws {
        let api=ChatTestTransport();let service=TaskService(client:api)
        try api.enqueue(["deleted":"7","assets_deleted":1,"assets_detached":2,"traffic_deleted":3,"files_deleted":true,"findings_deleted":4,"llm_records_deleted":5,"cleanup_warning":"private-secret /guest/path"])
        var options=TaskDeletionOptions();options.deleteFiles=true;options.deleteFindings=true
        let result=try await service.delete(id:"7",options:options)
        XCTAssertEqual(result.deleted,"7");XCTAssertEqual(result.assetsDeleted,1);XCTAssertEqual(result.assetsDetached,2);XCTAssertEqual(result.trafficDeleted,3)
        XCTAssertTrue(result.filesDeleted);XCTAssertEqual(result.findingsDeleted,4);XCTAssertEqual(result.llmRecordsDeleted,5);XCTAssertTrue(result.hasCleanupWarning)
        XCTAssertFalse(String(describing:result).contains("private-secret"));XCTAssertEqual(api.calls.count,1);XCTAssertEqual(api.calls[0].method,"DELETE")
        let body=try object(api.calls[0].body);XCTAssertEqual(body.count,5);XCTAssertEqual(body["delete_files"] as? Bool,true);XCTAssertEqual(body["delete_assets"] as? Bool,false)
    }
    @MainActor func testInvalidIDsAndCreationOptionsNeverIssueRequests() async throws {
        let api=ChatTestTransport();let service=TaskService(client:api)
        for id in ["","0","-1","1?x=1","1/2","1\r\nHost:x","9223372036854775808","１"] {
            do {_ = try await service.detail(id:id);XCTFail("Invalid ID accepted")} catch {}
        }
        do {_ = try await service.controlBatch(ids:[],action:.pause);XCTFail("Empty batch")} catch {}
        do {_ = try await service.controlBatch(ids:(1...101).map(String.init),action:.pause);XCTFail("Oversized batch")} catch {}
        for change in 0..<7 {
            var draft=TaskCreateDraft();draft.description="d";draft.goal="g"
            switch change {case 0:draft.goal=" ";case 1:draft.timeoutSeconds = -1;case 2:draft.categoryId=0;case 3:draft.llmProfileIds=[1,1];case 4:draft.sourceTaskIds=["1","01"];case 5:draft.companyIds=[0];default:draft.companyIds=Array(1...33)}
            do {_ = try await service.create(draft);XCTFail("Invalid draft accepted")} catch {}
        }
        XCTAssertTrue(api.calls.isEmpty)
    }
    @MainActor func testMalformedEnvelopesCountersAndMutationOwnersAreRejected() async throws {
        let api=ChatTestTransport();let service=TaskService(client:api)
        for value in [["unexpected":true],["tasks":[try task("7"),try task("7")],"active":"7"]] as [[String:Any]] {
            try api.enqueue(value);do {_ = try await service.list();XCTFail("Bad list accepted")} catch {}
        }
        var bad=try task("7");bad["goals_met"] = -1
        try api.enqueue(bad);do {_ = try await service.detail(id:"7");XCTFail("Negative counter accepted")} catch {}
        try api.enqueue(task("8"));do {_ = try await service.update(id:"7",patch:.init(pinned:true));XCTFail("Wrong owner accepted")} catch {}
        try api.enqueue(["id":"7","paused":false,"queued":false,"status":"running"]);do {_ = try await service.control(id:"7",action:.pause);XCTFail("Wrong control accepted")} catch {}
        try api.enqueue(["items":[]]);do {_ = try await service.controlBatch(ids:["7"],action:.pause);XCTFail("Missing result accepted")} catch {}
    }
    @MainActor func testHTTPFailuresAndUnexpectedAcceptedStatusesAreNotSuccessOrRetried() async throws {
        let api=ChatTestTransport();let service=TaskService(client:api)
        for status in [401,403,409,503,202] {
            try api.enqueue(["error":"private-secret"],status:status)
            do {_ = try await service.detail(id:"7");XCTFail("HTTP failure accepted")} catch {XCTAssertFalse(error.localizedDescription.contains("private-secret"))}
        }
        XCTAssertEqual(api.calls.count,5)
    }
    @MainActor func testOptionalFieldsUnknownStatusAndEmptySnapshots() async throws {
        let api = ChatTestTransport(); let service = TaskService(client: api)
        var item = try task("7")
        item.merge(["category_id": 5, "category_name": "custom 中文", "pinned_at": "raw", "llm_profile_id": 8,
                    "llm_profile_ids": [8, 9], "active_llm_profile_id": 9, "llm_failover_reason": "custom 한국어",
                    "source_task_ids": ["2"], "archive_blocked_by_task_id": "3", "company_ids": [4],
                    "engine_mode": "future", "status": "future-state"]) { _, new in new }
        try api.enqueue(item)
        let record = try await service.detail(id: "7")
        XCTAssertEqual(record.categoryId, 5); XCTAssertEqual(record.categoryName, "custom 中文")
        XCTAssertEqual(record.llmProfileId, 8); XCTAssertEqual(record.activeLlmProfileId, 9)
        XCTAssertEqual(record.llmFailoverReason, "custom 한국어"); XCTAssertEqual(record.archiveBlockedByTaskId, "3")
        XCTAssertEqual(record.status, "future-state"); XCTAssertEqual(record.engineMode, "future")
        try api.enqueue(["tasks": [], "active": "7"])
        let concurrent = try await service.list(); XCTAssertEqual(concurrent.activeID, "7")
        try api.enqueue(["tasks": []]); let empty = try await service.list(); XCTAssertNil(empty.activeID)
        try api.enqueue(["id": "7", "paused": false, "queued": false, "status": "running"])
        let resumed = try await service.control(id: "7", action: .resume); XCTAssertFalse(resumed.queued)
        try api.enqueue(["items": [["id": "7", "ok": true, "status": "paused"]]])
        let paused = try await service.controlBatch(ids: ["7"], action: .pause); XCTAssertFalse(paused[0].queued)
    }
    @MainActor func testMalformedIdentityTypesAndLimitsStayAtBoundary() async throws {
        let api = ChatTestTransport(); let service = TaskService(client: api)
        for change in [["id": "01"], ["exploration_id": 0], ["source_task_ids": ["01"]],
                       ["archive_blocked_by_task_id": "x"], ["category_id": 0], ["llm_profile_ids": [-1]],
                       ["company_ids": [0]], ["in_flight": -1], ["tokens": NSNull()]] as [[String: Any]] {
            var item = try task("7"); item.merge(change) { _, new in new }; try api.enqueue(item)
            do { _ = try await service.detail(id: "7"); XCTFail("Malformed record accepted") }
            catch { XCTAssertTrue(error is BackendAPIError) }
        }
        for list in [["tasks": "wrong"], ["tasks": [], "active": "01"]] as [[String: Any]] {
            try api.enqueue(list)
            do { _ = try await service.list(); XCTFail("Malformed snapshot accepted") } catch {}
        }
        try api.enqueue(["items": [["id": "8", "ok": true, "status": "running"]]])
        do { _ = try await service.controlBatch(ids: ["7"], action: .resume); XCTFail("Wrong batch owner") } catch {}
        try api.enqueue(["items": [["id": "7", "ok": true, "status": "paused"]]])
        do { _ = try await service.controlBatch(ids: ["7"], action: .resume); XCTFail("Wrong batch status") } catch {}
        for status in [200, 201] {
            try api.enqueue(["bad": true], status: status)
            var draft = TaskCreateDraft(); draft.description = "d"; draft.goal = "g"
            do { _ = try await service.create(draft); XCTFail("Unconfirmed create accepted") } catch {}
        }
        let oversized = Data(#"{"tasks":[],"active":""}"#.utf8) + Data(repeating: 32, count: 4 * 1024 * 1024)
        let otherwiseValid = try BackendJSONCoding.decode(TaskListSnapshot.self, from: oversized)
        XCTAssertTrue(otherwiseValid.tasks.isEmpty)
        api.replies.append(.init(status: 200, body: oversized))
        do { _ = try await service.list(); XCTFail("Oversize accepted") } catch {}
    }
    @MainActor func testDeletionWarningAbsentAndCounterOwnerValidation() async throws {
        let api = ChatTestTransport(); let service = TaskService(client: api)
        let base: [String: Any] = ["deleted": "7", "assets_deleted": 0, "assets_detached": 0, "traffic_deleted": 0,
                                  "files_deleted": false, "findings_deleted": 0, "llm_records_deleted": 0]
        try api.enqueue(base); let result = try await service.delete(id: "7"); XCTAssertFalse(result.hasCleanupWarning)
        for change in [["deleted": "8"], ["assets_deleted": -1]] as [[String: Any]] {
            var body = base; body.merge(change) { _, new in new }; try api.enqueue(body)
            do { _ = try await service.delete(id: "7"); XCTFail("Invalid deletion confirmation") } catch {}
        }
    }
    @MainActor func testTypedValidationRelocalizesAndCancellationNeverSends() async throws {
        for error in TaskInputError.allCases {
            let stored = AppErrorMessage(error)
            XCTAssertEqual(stored.text(language: .english), AppStrings.text(error.key, language: .english))
            XCTAssertEqual(AppErrorText.text(error, language: .japanese), stored.text(language: .japanese))
            XCTAssertNotEqual(stored.text(language: .english), stored.text(language: .japanese))
            XCTAssertEqual(error.errorDescription, stored.text(language: .japanese))
        }
        let api = ChatTestTransport(); let service = TaskService(client: api)
        let pending = Task { @MainActor in try await service.list() }; pending.cancel()
        do { _ = try await pending.value; XCTFail("Cancelled operation succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(api.calls.isEmpty)
        var draft = TaskCreateDraft(); draft.description = "d"; draft.goal = "g"; draft.sourceTaskIds = ["bad"]
        do { _ = try draft.encoded(); XCTFail("Invalid source") } catch { XCTAssertEqual(error as? TaskInputError, .invalidCreation) }
    }

    @MainActor func testCancellationAfterDispatchDoesNotAcceptResponseOrRetry() async throws {
        let api = ChatTestTransport(); let service = TaskService(client: api)
        let (started, signal) = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<BackendHTTPResponse, Never>?
        api.handler = { _ in
            await withCheckedContinuation { continuation in
                release = continuation; signal.yield(())
            }
        }
        let pending = Task { @MainActor in try await service.update(id: "7", patch: .init(pinned: true)) }
        var iterator = started.makeAsyncIterator(); _ = await iterator.next()
        pending.cancel()
        let response = try ChatTestTransport.response(task("7"))
        try XCTUnwrap(release).resume(returning: response)
        do { _ = try await pending.value; XCTFail("Cancelled response accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(api.calls.count, 1); signal.finish()
    }

}
