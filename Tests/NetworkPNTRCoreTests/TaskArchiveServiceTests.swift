import XCTest
@testable import NetworkPNTRCore

final class TaskArchiveServiceTests: XCTestCase {
    private let big: Int64 = 9007199254740993
    private func data(id: Int64 = 9007199254740993, task: Int64 = 9007199254740994, state: String = "ready") -> Data {
        Data("""
        {"id":\(id),"task_id":\(task),"state":"\(state)","phase":"queued","progress":0,"error":"private error token","warnings":["private warning"],"format_version":3,"sha256":"\(String(repeating:"a",count:64))","original_size":9007199254740993,"compressed_size":12,"task_name":"\\ufeffe\\u0301 中文 한국어","task_description":"\\ufeffliteral e\\u0301","task_goal":"goal","original_status":"paused","category_id":7,"category_name":"category","source_task_ids":[4,5],"remaining_timeout_seconds":12,"data_counts":{"tasks":9007199254740993},"aggregate_stats":{"tokens":{"calls":2,"input_tokens":9007199254740993},"skills":{"e\\u0301":2},"tools":{"中文":3},"findings":{"high":1},"future_array":[1,2]},"requested_at":"r","created_at":"c","updated_at":"u"}
        """.utf8)
    }
    private func object(_ body: Data?) throws -> [String:Any] { try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(body)) as? [String:Any]) }
    @MainActor private func rejected(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Invalid archive contract accepted",file:file,line:line) } catch {}
    }
    func testRecordRetainsExactNumbersAndBytesButNotWorkerMessages() throws {
        let row = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:data())
        XCTAssertEqual(row.id,big); XCTAssertEqual(row.taskId,big+1); XCTAssertEqual(row.originalSize,big)
        XCTAssertEqual(Data(row.taskName.utf8),Data("\u{FEFF}e\u{301} 中文 한국어".utf8))
        XCTAssertEqual(Data(row.taskDescription.utf8),Data("\u{FEFF}literal e\u{301}".utf8))
        XCTAssertEqual(row.sourceTaskIds,[4,5]); XCTAssertEqual(row.dataCounts["tasks"],big)
        XCTAssertEqual(row.aggregateStats.tokens?.inputTokens,big); XCTAssertEqual(row.aggregateStats.skills["e\u{301}"],2)
        XCTAssertTrue(row.hasError); XCTAssertEqual(row.warningCount,1); XCTAssertFalse(String(describing:row).contains("private"))
        var future = try object(data()); future["format_version"] = 99; future["state"] = "future_state"; future["phase"] = "future_phase"
        let decoded = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:JSONSerialization.data(withJSONObject:future))
        XCTAssertEqual(decoded.state,"future_state"); XCTAssertEqual(decoded.formatVersion,99)
        XCTAssertFalse(TaskArchiveSemantics.canRestore(decoded)); XCTAssertFalse(TaskArchiveSemantics.supportedFormat(decoded))
    }
    func testMalformedSchemaAndNegativeCountersAreRejected() throws {
        for (key,value): (String,Any) in [("id",0),("task_id",-1),("progress",101),("progress",-1),("format_version",0),("original_size",-1),("compressed_size",-1),("remaining_timeout_seconds",-1),("category_id",0),("source_task_ids",[1,1]),("data_counts",["tasks":-1]),("aggregate_stats",["tokens":["calls":-1]]),("aggregate_stats",["skills":["x":-1]]),("sha256","wrong")] {
            var row = try object(data()); row[key] = value
            XCTAssertThrowsError(try BackendJSONCoding.decode(TaskArchiveRecord.self,from:JSONSerialization.data(withJSONObject:row)),key)
        }
        var row = try object(data()); row.removeValue(forKey:"task_name")
        XCTAssertThrowsError(try BackendJSONCoding.decode(TaskArchiveRecord.self,from:JSONSerialization.data(withJSONObject:row)))
        for key in ["warnings","source_task_ids","data_counts","aggregate_stats"] { row[key] = NSNull() }
        row["task_name"] = "name"; row["sha256"] = ""
        let empty = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:JSONSerialization.data(withJSONObject:row))
        XCTAssertEqual(empty.warningCount,0); XCTAssertTrue(empty.sourceTaskIds.isEmpty); XCTAssertTrue(empty.dataCounts.isEmpty)
    }
    @MainActor func testListQueryPreservesPlusUnicodeAndPaginationEnvelope() async throws {
        let api = ChatTestTransport(), service = TaskArchiveService(client:api)
        let query = "C++ & 日本e\u{301} \u{FEFF} {x}", state = "ready&state=delete"
        try api.enqueue(["items":[object(data())],"total":0,"page":2,"size":10])
        let page = try await service.list(page:2,size:10,query:query,state:state)
        XCTAssertEqual(page.items.count,1); XCTAssertEqual(page.total,0); XCTAssertEqual(page.page,2)
        let parts = api.calls[0].path.split(separator:"?",maxSplits:1); XCTAssertEqual(parts[0],"/api/task-archives")
        var decoded: [String:String] = [:]
        for entry in parts[1].split(separator:"&") { let pair = entry.split(separator:"=",maxSplits:1,omittingEmptySubsequences:false); decoded[String(pair[0])] = String(pair[1]).replacingOccurrences(of:"+",with:" ").removingPercentEncoding }
        XCTAssertEqual(Data(try XCTUnwrap(decoded["q"]).utf8),Data(query.utf8)); XCTAssertEqual(decoded["state"],state)
        try api.enqueue(["items":NSNull(),"total":0,"page":1,"size":20]); let empty = try await service.list(); XCTAssertTrue(empty.items.isEmpty)
        XCTAssertEqual(api.calls[1].path,"/api/task-archives?page=1&size=20")
        for bad in [["total":0,"page":1,"size":20] as [String:Any],["items":[],"total":-1,"page":1,"size":20],["items":[],"total":0,"page":2,"size":20],["items":[try object(data()),try object(data())],"total":2,"page":1,"size":20]] {
            try api.enqueue(bad); await rejected { _ = try await service.list() }
        }
    }
    @MainActor func testSingleOperationsRequire202OwnerAndQueuedState() async throws {
        let api = ChatTestTransport(), service = TaskArchiveService(client:api)
        api.replies.append(.init(status:200,body:data())); _ = try await service.detail(id:big)
        api.replies.append(.init(status:202,body:data(id:8,task:7,state:"archive_queued"))); _ = try await service.queue(taskID:"0007")
        api.replies.append(.init(status:202,body:data(state:"restore_queued"))); _ = try await service.restore(id:big)
        api.replies.append(.init(status:202,body:data(state:"delete_queued"))); _ = try await service.delete(id:big)
        XCTAssertEqual(api.calls.map(\.method),["GET","POST","POST","DELETE"])
        XCTAssertEqual(api.calls.map(\.path),["/api/task-archives/\(big)","/api/tasks/7/archive","/api/task-archives/\(big)/restore","/api/task-archives/\(big)"])
        XCTAssertTrue(api.calls.allSatisfy{$0.body == nil})
        for response in [BackendHTTPResponse(status:200,body:data(state:"restore_queued")),.init(status:202,body:data(id:8,state:"restore_queued")),.init(status:202,body:data(state:"ready"))] {
            api.replies.append(response); await rejected { _ = try await service.restore(id:big) }
        }
        api.replies.append(.init(status:202,body:data(task:8,state:"archive_queued"))); await rejected { _ = try await service.queue(taskID:"7") }
    }
    @MainActor func testReorderedPartialBatchReceiptsUseSetOwnership() async throws {
        let api = ChatTestTransport(), service = TaskArchiveService(client:api)
        try api.enqueue(["items":[["id":"8","ok":true,"queued":true,"archive_id":big],["id":"7","ok":false,"queued":false,"error":"private task"]]],status:202)
        let live = try await service.queueBatch(taskIDs:["0007","8","7"])
        XCTAssertEqual(live.map(\.id),["8","7"]); XCTAssertEqual(live.first?.archiveId,big); XCTAssertFalse(String(describing:live).contains("private"))
        XCTAssertEqual(try object(api.calls[0].body)["task_ids"] as? [String],["7","8"])
        try api.enqueue(["items":[["id":"8","ok":false,"queued":false,"archive_id":8],["id":String(big),"ok":true,"queued":true,"archive_id":big]]],status:202)
        let restored = try await service.restoreBatch(ids:[big,8,big]); XCTAssertEqual(restored.map(\.id),["8",String(big)])
        XCTAssertEqual(try object(api.calls[1].body)["archive_ids"] as? [Int64],[big,8])
        try api.enqueue(["items":[["id":"8","ok":true,"queued":true,"archive_id":8]]],status:202)
        _ = try await service.deleteBatch(ids:[8]); XCTAssertEqual(api.calls.last?.path,"/api/task-archives/delete/batch")
        try api.enqueue(["items":[["id":"7","ok":true,"queued":true,"archive_id":8]]],status:202)
        _ = try await service.queueBatch(taskIDs:Array(repeating:"7",count:101))
    }
    @MainActor func testInvalidBatchQueriesAndMalformedReceiptsNeverConfirm() async throws {
        let api = ChatTestTransport(), service = TaskArchiveService(client:api)
        for bad: Any in [["items":[["id":"9","ok":true,"queued":true,"archive_id":9]]],["items":[["id":"7","ok":true,"queued":false,"archive_id":8]]],["items":[["id":"7","ok":true,"queued":true]]],["items":[["id":"7","ok":false,"queued":true]]]] {
            try api.enqueue(bad,status:202); await rejected { _ = try await service.queueBatch(taskIDs:["7"]) }
        }
        try api.enqueue(["items":[["id":"7","ok":true,"queued":true,"archive_id":8],["id":"8","ok":true,"queued":true,"archive_id":8]]],status:202)
        await rejected { _ = try await service.queueBatch(taskIDs:["7","8"]) }
        try api.enqueue(["items":[["id":"7","ok":true,"queued":true,"archive_id":8]]],status:202)
        await rejected { _ = try await service.restoreBatch(ids:[7]) }
        let count = api.calls.count
        for ids in [[],[0],[-1],Array(repeating:Int64(8),count:101)] { await rejected { _ = try await service.deleteBatch(ids:ids) } }
        for ids in [[],["0"],["7/../x"],(1...101).map(String.init)] { await rejected { _ = try await service.queueBatch(taskIDs:ids) } }
        await rejected { _ = try await service.list(page:0) }; await rejected { _ = try await service.list(page:Int64.min) }; await rejected { _ = try await service.list(size:0) }; await rejected { _ = try await service.list(size:101) }
        await rejected { _ = try await service.list(page:Int64.max,size:100) }; await rejected { _ = try await service.list(query:String(repeating:"x",count:4097)) }
        await rejected { _ = try await service.list(state:String(repeating:"x",count:129)) }; await rejected { _ = try await service.detail(id:0) }
        XCTAssertEqual(api.calls.count,count)
        var valid = data(); valid.append(Data(repeating:32,count:4*1024*1024)); api.replies.append(.init(status:200,body:valid))
        await rejected { _ = try await service.detail(id:big) }
        try api.enqueue(["error":"private"],status:409)
        do { _ = try await service.restore(id:big); XCTFail("409 accepted") } catch BackendAPIError.status(409) {}
    }
    @MainActor func testExplicitRetryAndCancellationDoNotInferCompletion() async throws {
        let api = ChatTestTransport(), service = TaskArchiveService(client:api)
        for (failed,queued) in [("archive_failed","archive_queued"),("restore_failed","restore_queued"),("delete_failed","delete_queued")] {
            let row = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:data(id:8,task:7,state:failed))
            api.replies.append(.init(status:202,body:data(id:8,task:7,state:queued))); _ = try await service.retry(row)
        }
        XCTAssertEqual(api.calls.map(\.path),["/api/tasks/7/archive","/api/task-archives/8/restore","/api/task-archives/8"])
        let ready = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:data()); await rejected { _ = try await service.retry(ready) }
        let count = api.calls.count
        let before = Task { try await service.restore(id:self.big) }; before.cancel()
        do { _ = try await before.value; XCTFail("Precancel accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(api.calls.count,count)
        api.handler = { _ in withUnsafeCurrentTask{$0?.cancel()}; return .init(status:202,body:self.data(state:"restore_queued")) }
        let after = Task { try await service.restore(id:self.big) }
        do { _ = try await after.value; XCTFail("Postcancel accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(api.calls.count,count+1)
    }
    func testStateEligibilityAndLabelsUseExplicitEnglishJapanese() throws {
        XCTAssertEqual(TaskArchiveSemantics.states.count,10); XCTAssertEqual(TaskArchiveSemantics.phases.count,19)
        for state in TaskArchiveSemantics.states {
            let key = TaskArchiveSemantics.stateKey(state)
            XCTAssertNotEqual(key,.taskArchiveUnknownState)
            XCTAssertNotEqual(AppStrings.text(key,language:.english),AppStrings.text(key,language:.japanese))
            let row = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:data(state:state))
            XCTAssertEqual(TaskArchiveSemantics.canRestore(row),["ready","restore_failed"].contains(state))
            XCTAssertEqual(TaskArchiveSemantics.canDelete(row),["ready","delete_failed"].contains(state))
            XCTAssertEqual(TaskArchiveSemantics.canRetry(row),["archive_failed","restore_failed","delete_failed"].contains(state))
            XCTAssertEqual(TaskArchiveSemantics.processing(state),["archive_queued","archiving","restore_queued","restoring","delete_queued","deleting"].contains(state))
        }
        for phase in TaskArchiveSemantics.phases {
            let key = TaskArchiveSemantics.phaseKey(phase); XCTAssertNotEqual(key,.taskArchiveUnknownPhase)
            XCTAssertNotEqual(AppStrings.text(key,language:.english),AppStrings.text(key,language:.japanese))
        }
        XCTAssertEqual(TaskArchiveSemantics.stateKey("한국어 unknown"),.taskArchiveUnknownState)
        XCTAssertEqual(TaskArchiveSemantics.phaseKey("未知"),.taskArchiveUnknownPhase)
        for error in [TaskArchiveInputError.invalid,.queryLimits,.batch,.action] {
            XCTAssertEqual(AppErrorText.text(error,language:.english),AppErrorMessage(error).text(language:.english))
            XCTAssertNotEqual(AppErrorMessage(error).text(language:.english),AppErrorMessage(error).text(language:.japanese))
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"task-contract",withExtension:"json",subdirectory:"Fixtures"))
        let root = try object(Data(contentsOf:url)); var task = try XCTUnwrap(root["task"] as? [String:Any])
        task["status"] = "paused"; task["queued"] = false; task["archive_blocked_by_task_id"] = "7"
        func record() throws -> TaskRecord { try BackendJSONCoding.decode(TaskRecord.self,from:JSONSerialization.data(withJSONObject:task)) }
        XCTAssertFalse(TaskArchiveSemantics.canArchive(try record())); XCTAssertTrue(TaskArchiveSemantics.canArchive(try record(),batch:true))
        task["queued"] = true; XCTAssertFalse(TaskArchiveSemantics.canArchive(try record(),batch:true))
        task["queued"] = false; task["status"] = "running"; XCTAssertFalse(TaskArchiveSemantics.canArchive(try record(),batch:true))
        task["status"] = "done"; task["archive_blocked_by_task_id"] = NSNull(); XCTAssertTrue(TaskArchiveSemantics.canArchive(try record()))
    }

    func testCounterNamesRetainByteIdentityAndCannotHideNegativeEntries() throws {
        let original = String(decoding:data(),as:UTF8.self)
        let key = #""skills":{"e\u0301":2}"#
        let changed = original.replacingOccurrences(of:key,with:#""skills":{"é":2,"e\u0301":3,"\ufeffraw_key":4,"raw_key":5}"#)
        XCTAssertNotEqual(changed,original)
        let row = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data(changed.utf8))
        XCTAssertEqual(row.aggregateStats.skills.count,4)
        XCTAssertEqual(row.aggregateStats.skills["é"],2); XCTAssertEqual(row.aggregateStats.skills["e\u{301}"],3)
        XCTAssertEqual(row.aggregateStats.skills["\u{FEFF}raw_key"],4); XCTAssertEqual(row.aggregateStats.skills["raw_key"],5)
        for values in [#""skills":{"é":-1,"e\u0301":3}"#,#""skills":{"é":3,"e\u0301":-1}"#] {
            let invalid = original.replacingOccurrences(of:key,with:values)
            XCTAssertThrowsError(try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data(invalid.utf8)))
        }
    }

    func testRawMapPathsAndBoundedJSONSyntax() throws {
        let original = String(decoding:data(),as:UTF8.self), key = #""skills":{"e\u0301":2}"#
        let first = original.replacingOccurrences(of:key,with:#""skills":{"é":2,"e\u0301":3,"\ufeffraw_key":4,"raw_key":5}"#)
        let second = String(decoding:data(id:8,task:9),as:UTF8.self).replacingOccurrences(of:key,with:#""skills":{"e\u0301":7}"#)
        let pageData = Data((#"{"items":["# + first + "," + second + #"],"total":2,"page":1,"size":20}"#).utf8)
        let page = try BackendJSONCoding.decode(TaskArchivePage.self,from:pageData)
        XCTAssertEqual(page.items[0].aggregateStats.skills["e\u{301}"],3); XCTAssertEqual(page.items[1].aggregateStats.skills["e\u{301}"],7)
        XCTAssertEqual(Set(page.items[0].aggregateStats.skills.entries.map(\.id)).count,4)
        for raw in [#""skills":{}"#,#""skills":null"#] {
            let value = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data(original.replacingOccurrences(of:key,with:raw).utf8))
            XCTAssertTrue(value.aggregateStats.skills.isEmpty)
        }
        for raw in [#""skills":{"x":-1}"#,#""skills":{"x":9223372036854775808}"#,#""skills":{"x":true}"#,#""skills":{"x":null}"#,#""skills":{"x":1.0}"#,#""skills":{"x":1e2}"#,#""skills":{"x":01}"#,#""skills":{"x":+1}"#,#""skills":{"x":1,"x":2}"#,#""skills":{"x":"1"}"#] {
            XCTAssertThrowsError(try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data(original.replacingOccurrences(of:key,with:raw).utf8)))
        }
        func withIgnored(_ raw: String) -> Data { Data((String(original.dropLast()) + #", "ignored":"# + raw + "}").utf8) }
        for token in ["[]","{}","[true,false,null,-1,1.25e+2,1E2,-1e-2,0.0,-0]",#""escaped\"slash\\\uD83D\uDE00""#,#"{"data_counts":{"x":"not a counter"},"aggregate_stats":{"skills":{"x":"ignored"}}}"#] {
            let value = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:withIgnored(token)); XCTAssertEqual(value.id,big)
        }
        for token in ["tru","true false","1e","1.","--1","[1,]",#"{"x":1,}"#,#""\u00ZZ""#,#""\uD800""#] {
            XCTAssertThrowsError(try BackendJSONCoding.decode(TaskArchiveRecord.self,from:withIgnored(token)))
        }
        XCTAssertThrowsError(try BackendJSONCoding.decode(TaskArchiveRecord.self,from:withIgnored(String(repeating:"[",count:130)+"0"+String(repeating:"]",count:130))))
        XCTAssertThrowsError(try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data((original+" trailing").utf8)))
        XCTAssertThrowsError(try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data(original.dropLast().utf8)))
        for alias in [#", "dataCounts":{"x":-1}}"#,#", "aggregate__stats":{"skills":{"x":-1}}}"#] {
            XCTAssertThrowsError(try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data((String(original.dropLast())+alias).utf8)))
        }
        var huge = data(); huge.append(Data(repeating:32,count:4*1024*1024))
        XCTAssertThrowsError(try BackendJSONCoding.decode(TaskArchiveRecord.self,from:huge))
    }

}
