import XCTest
@testable import NetworkPNTRCore

@MainActor private final class ArchiveExerciseAPI: BackendJSONTransport, TaskArchiveFixtureControlling {
    var live: Set<Int64> = [7101,7102]
    var records: [Int64:(task:Int64,state:String)] = [:]
    var laggedActive: [String] = []
    var laggedLists: [Set<Int64>] = []
    var partialBatch = false
    var rejectHide = false
    var auditFailure = false
    var next: Int64 = 31
    var hidden = false
    var pending = false
    var badFile = false
    var badName = false
    var wrongOwner = false
    var wrongReceipt = false
    var mismatchedSingleReceipt: Int?
    var singleWrites = 0
    var calls: [(String,String)] = []
    var controls: [String] = []
    var audits = 0
    var onRead: (() -> Void)?
    func verifyNoAgentActivity() async throws { audits += 1; if auditFailure { throw RuntimeError.integrity("fixture audit failed") } }
    func setPackageHidden(_ value: Bool, target: TaskArchiveFixtureTarget) async throws {
        XCTAssertEqual(records[target.archiveID]?.task,7101); XCTAssertEqual(target.sha256,String(repeating:"a",count:64))
        controls.append(value ? "hide" : "repair"); if value && rejectHide { throw RuntimeError.integrity("fixture hide rejected") }; hidden = value
    }
    func archive(_ id: Int64,_ task: Int64,_ state: String, overrideTask: Int64? = nil) throws -> BackendHTTPResponse {
        let name = task == 7101 ? TaskArchiveExercise.name : "T17 second", description = task == 7101 ? TaskArchiveExercise.description : "Archive fixture second"
        return try ChatTestTransport.response(["error":state == "restore_failed" ? "fixed missing fixture package" : "","id":id,"task_id":overrideTask ?? (wrongOwner ? 99 : task),"state":state,"phase":"ready","progress":state == "ready" ? 100 : 0,"format_version":3,"sha256":String(repeating:"a",count:64),"original_size":100,"compressed_size":50,"task_name":name,"task_description":description,"task_goal":TaskArchiveExercise.goal,"original_status":"done","category_id":7100,"category_name":"T17 archive category","remaining_timeout_seconds":0,"data_counts":["tasks":1,"explorations":1],"requested_at":"r","created_at":"c","updated_at":"u"])
    }
    func task(_ id: Int64) throws -> [String:Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"task-contract",withExtension:"json",subdirectory:"Fixtures"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]); var row = try XCTUnwrap(root["task"] as? [String:Any])
        row["id"] = String(id); row["exploration_id"] = id; row["name"] = id == 7101 ? (badName ? "é 中文 한국어" : TaskArchiveExercise.name) : "T17 second"
        row["description"] = id == 7101 ? TaskArchiveExercise.description : "Archive fixture second"; row["goal"] = TaskArchiveExercise.goal
        row["status"] = "done"; row["paused"] = false; row["queued"] = false; row["in_flight"] = 0
        row["category_id"] = 7100; row["category_name"] = "T17 archive category"; row["llm_profile_id"] = NSNull(); row["llm_profile_ids"] = []; row["active_llm_profile_id"] = NSNull(); row["source_task_ids"] = []
        return row
    }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls.append((method,path)); if method == "GET" { onRead?() }
        if path == "/api/tasks" {
            let visible = laggedLists.isEmpty ? live : laggedLists.removeFirst()
            return try ChatTestTransport.response(["tasks":try visible.sorted().map{try task($0)},"active":laggedActive.isEmpty ? "" : laggedActive.removeFirst()])
        }
        if path.hasPrefix("/api/tasks/"), method == "GET" {
            let id = Int64(path.split(separator:"/").last!)!; return live.contains(id) ? try ChatTestTransport.response(task(id)) : .init(status:404,body:Data())
        }
        if path.hasPrefix("/api/workspace/download?") {
            let name = URLComponents(string:path)?.queryItems?.first?.value ?? ""
            if name.hasPrefix("archives/tasks/") {
                let exists = records.contains { name == "archives/tasks/task-\($0.value.task)-\($0.key).tar.zst" }
                return .init(status:exists ? 200 : 404,body:Data())
            }
            let file = try XCTUnwrap(TaskArchiveExercise.files.first{$0.path.utf8.elementsEqual(name.utf8)})
            if !live.contains(file.taskID) { return .init(status:404,body:Data()) }
            return .init(status:200,body:badFile ? Data("wrong bytes".utf8) : file.data)
        }
        if path.hasPrefix("/api/task-archives?") {
            // Keep raw fixture JSON; a Foundation object roundtrip strips leading FEFF values.
            let values = try records.sorted{$0.key < $1.key}.map { String(decoding:try archive($0.key,$0.value.task,$0.value.state).body,as:UTF8.self) }
            return .init(status:200,body:Data("{\"items\":[\(values.joined(separator:","))],\"total\":\(values.count),\"page\":1,\"size\":20}".utf8))
        }
        if path == "/api/tasks/archive/batch" {
            var items: [[String:Any]] = []
            for task in [7102,7101] as [Int64] {
                if partialBatch && task == 7102 { items.append(["id":"7102","ok":false,"queued":false]); continue }
                let id = next; next += 1; records[id] = (task,pending ? "archiving" : "ready"); live.remove(task); items.append(["id":String(task),"ok":true,"queued":true,"archive_id":id]) }
            return try ChatTestTransport.response(["items":items],status:202)
        }
        if path.hasPrefix("/api/tasks/"), path.hasSuffix("/archive") {
            singleWrites += 1
            let task = Int64(path.split(separator:"/")[2])!, id = next; next += 1; records[id] = (task,"ready"); live.remove(task)
            let row = try archive(id,task,wrongReceipt ? "ready" : "archive_queued",overrideTask:singleWrites == mismatchedSingleReceipt ? 99 : nil); return .init(status:202,body:row.body)
        }
        let id = Int64(path.split(separator:"/")[2])!
        guard let record = records[id] else { return .init(status:404,body:Data()) }
        if method == "DELETE" {
            singleWrites += 1
            records.removeValue(forKey:id); return .init(status:202,body:try archive(id,record.task,"delete_queued",overrideTask:singleWrites == mismatchedSingleReceipt ? 99 : nil).body)
        }
        if method == "POST", path.hasSuffix("/restore") {
            singleWrites += 1
            if hidden { records[id] = (record.task,"restore_failed") } else { records.removeValue(forKey:id); live.insert(record.task) }
            return .init(status:202,body:try archive(id,record.task,"restore_queued",overrideTask:singleWrites == mismatchedSingleReceipt ? 99 : nil).body)
        }
        return try archive(id,record.task,record.state)
    }
}

final class TaskArchiveExerciseTests: XCTestCase {
    @MainActor func testTwoPhaseExerciseRequiresActualStatesExactBytesAndPersistedCheckpoint() async throws {
        let api = ArchiveExerciseAPI(); let exercise = TaskArchiveExercise(client:api,fixture:api,sleep:{_ in})
        let checkpoint = try await exercise.runBeforeRestart(); XCTAssertEqual(checkpoint.checks,TaskArchiveExercise.beforeRestartChecks)
        XCTAssertEqual(api.live,[]); XCTAssertEqual(api.records.count,1); XCTAssertEqual(api.controls,["hide","repair"])
        let data = try JSONEncoder().encode(checkpoint), restored = try JSONDecoder().decode(TaskArchiveCheckpoint.self,from:data)
        let report = try await exercise.runAfterRestart(restored); XCTAssertEqual(report.checks,TaskArchiveExercise.expectedChecks)
        XCTAssertTrue(report.passed); XCTAssertEqual(api.live,Set([7101])); XCTAssertTrue(api.records.isEmpty); XCTAssertEqual(api.audits,4)
        XCTAssertEqual(report.files.count,3); XCTAssertEqual(report.files.reduce(0){$0+$1.size},1056)
        XCTAssertFalse(api.calls.contains{$0.0 == "POST" && $0.1 == "/api/tasks" || $0.1.contains("/control") || $0.1.contains("/chat")})
        XCTAssertEqual(api.calls.filter{$0.0 == "POST" && $0.1.hasSuffix("/restore")}.count,3)
    }
    @MainActor func testBadInitialNameBytesOrFileNeverQueuesArchive() async throws {
        for name in [true,false] {
            let api = ArchiveExerciseAPI(); api.badName = name; api.badFile = !name
            do { _ = try await TaskArchiveExercise(client:api,fixture:api,sleep:{_ in}).runBeforeRestart(); XCTFail("corrupt fixture accepted") } catch {}
            XCTAssertFalse(api.calls.contains{$0.0 != "GET"})
        }
    }
    @MainActor func testPendingArchiveExhaustsFinitePollingWithoutAnotherWrite() async throws {
        let api = ArchiveExerciseAPI(); api.pending = true; var sleeps = 0
        do { _ = try await TaskArchiveExercise(client:api,fixture:api,sleep:{_ in sleeps += 1}).runBeforeRestart(); XCTFail("queued is not completion") } catch {}
        XCTAssertLessThanOrEqual(sleeps,120); XCTAssertGreaterThan(sleeps,0)
        XCTAssertEqual(api.calls.filter{$0.0 != "GET"}.count,1); XCTAssertTrue(api.controls.isEmpty)
    }
    @MainActor func testWrongArchiveOwnerAndWrongSingleReceiptFailClosed() async throws {
        for wrongOwner in [true,false] {
            let api = ArchiveExerciseAPI(); api.wrongOwner = wrongOwner; api.wrongReceipt = !wrongOwner
            do { _ = try await TaskArchiveExercise(client:api,fixture:api,sleep:{_ in}).runBeforeRestart(); XCTFail("wrong receipt accepted") } catch {}
            if wrongOwner { XCTAssertTrue(api.controls.isEmpty) }
        }
    }
    @MainActor func testCancellationAfterReadNeverStartsWrite() async throws {
        let api = ArchiveExerciseAPI()
        let task = Task { api.onRead = { withUnsafeCurrentTask{$0?.cancel()} }; return try await TaskArchiveExercise(client:api,fixture:api,sleep:{_ in}).runBeforeRestart() }
        do { _ = try await task.value; XCTFail("cancel ignored") } catch {}
        XCTAssertFalse(api.calls.contains{$0.0 != "GET"})
    }
    @MainActor func testForgedOrWrongPersistedCheckpointNeverRestores() async throws {
        let api = ArchiveExerciseAPI(); let exercise = TaskArchiveExercise(client:api,fixture:api,sleep:{_ in})
        let checkpoint = try await exercise.runBeforeRestart(); let data = try JSONEncoder().encode(checkpoint)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]); raw["checks"] = []
        let forged = try JSONDecoder().decode(TaskArchiveCheckpoint.self,from:JSONSerialization.data(withJSONObject:raw)); let count = api.calls.count
        do { _ = try await exercise.runAfterRestart(forged); XCTFail("forged checkpoint accepted") } catch {}
        XCTAssertEqual(api.calls.count,count)
        api.wrongOwner = true; let writes = api.calls.filter{$0.0 != "GET"}.count
        do { _ = try await exercise.runAfterRestart(checkpoint); XCTFail("foreign archive accepted") } catch {}
        XCTAssertEqual(api.calls.filter{$0.0 != "GET"}.count,writes)
    }
    @MainActor func testEverySingle202TaskOwnerMustMatchBeforeAnyFurtherRequest() async throws {
        for index in 1...5 {
            let api = ArchiveExerciseAPI(); api.mismatchedSingleReceipt = index
            let exercise = TaskArchiveExercise(client:api,fixture:api,sleep:{_ in})
            do {
                let checkpoint = try await exercise.runBeforeRestart()
                _ = try await exercise.runAfterRestart(checkpoint)
                XCTFail("A queued receipt for another task was accepted")
            } catch {}
            XCTAssertEqual(api.singleWrites,index); XCTAssertNotEqual(api.calls.last?.0,"GET")
        }
    }

    @MainActor func testLiveRegistryLagIsPolledWithoutAnotherMutation() async throws {
        let api = ArchiveExerciseAPI(); var sleeps = 0
        let exercise = TaskArchiveExercise(client:api,fixture:api,sleep:{_ in sleeps += 1},progress:{ stage in
            if stage == "bulk_archive" { api.laggedLists = [[7101,7102],[7102]] }
            if stage == "explicit_retry" { api.laggedLists = [[]] }
        })
        let checkpoint = try await exercise.runBeforeRestart(); XCTAssertGreaterThanOrEqual(sleeps,3)
        XCTAssertEqual(checkpoint.checks,TaskArchiveExercise.beforeRestartChecks); XCTAssertEqual(api.singleWrites,4)
    }
    @MainActor func testLateReadyResponseFailsStageDeadlineBeforeFaultMutation() async throws {
        let api = ArchiveExerciseAPI(); let base = ContinuousClock().now; var ticks = 0
        let exercise = TaskArchiveExercise(client:api,fixture:api,sleep:{_ in},now:{ ticks += 1; return base.advanced(by:.seconds(ticks > 2 ? 60 : 0)) })
        do { _ = try await exercise.runBeforeRestart(); XCTFail("late ready accepted") } catch {}
        XCTAssertEqual(api.calls.filter{$0.0 != "GET"}.count,1); XCTAssertTrue(api.controls.isEmpty)
    }
    @MainActor func testAuditOrFaultRejectionStopsBeforeUnprovenOperations() async throws {
        for auditFailure in [true,false] {
            let api = ArchiveExerciseAPI(); api.auditFailure = auditFailure; api.rejectHide = !auditFailure
            do { _ = try await TaskArchiveExercise(client:api,fixture:api,sleep:{_ in}).runBeforeRestart(); XCTFail("failed fixture control accepted") } catch {}
            if auditFailure { XCTAssertTrue(api.calls.isEmpty) }
            else { XCTAssertEqual(api.calls.filter{$0.0 != "GET"}.count,1); XCTAssertEqual(api.controls,["hide"]) }
        }
    }
    @MainActor func testPartialBatchAcceptanceDoesNotAdvanceOrRetry() async throws {
        let api = ArchiveExerciseAPI(); api.partialBatch = true
        do { _ = try await TaskArchiveExercise(client:api,fixture:api,sleep:{_ in}).runBeforeRestart(); XCTFail("partial acceptance claimed full exercise") } catch {}
        XCTAssertEqual(api.calls.filter{$0.0 != "GET"}.count,1); XCTAssertEqual(api.calls.last?.0,"POST"); XCTAssertTrue(api.controls.isEmpty)
    }
    @MainActor func testByteChangedCheckpointAndPrecancelledRunNeverStart() async throws {
        let api = ArchiveExerciseAPI(); let exercise = TaskArchiveExercise(client:api,fixture:api,sleep:{_ in})
        let checkpoint = try await exercise.runBeforeRestart(); var root = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(checkpoint)) as? [String:Any])
        var files = try XCTUnwrap(root["files"] as? [[String:Any]]); files[0]["path"] = "tasks/7101/workspace/fixture-é.txt"; root["files"] = files
        let changed = try JSONDecoder().decode(TaskArchiveCheckpoint.self,from:JSONSerialization.data(withJSONObject:root)); let count = api.calls.count
        do { _ = try await exercise.runAfterRestart(changed); XCTFail("NFC path accepted for NFD fixture") } catch {}
        XCTAssertEqual(api.calls.count,count)
        let cancelled = Task { try await exercise.runBeforeRestart() }; cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("precancelled run accepted") } catch {}
        XCTAssertEqual(api.calls.count,count)
    }

    @MainActor func testTransientActivePointerFromSeparateSnapshotIsWaitedOut() async throws {
        let api = ArchiveExerciseAPI(); var sleeps = 0
        let exercise = TaskArchiveExercise(client:api,fixture:api,sleep:{_ in sleeps += 1},progress:{ stage in if stage == "bulk_archive" { api.laggedActive = ["7101"] } })
        let checkpoint = try await exercise.runBeforeRestart(); XCTAssertEqual(checkpoint.checks,TaskArchiveExercise.beforeRestartChecks)
        XCTAssertGreaterThanOrEqual(sleeps,1); XCTAssertEqual(api.singleWrites,4)
    }

    @MainActor func testRunReportRequiresThreeAuditedPersistentBootsAndTerminalProof() async throws {
        let api = ArchiveExerciseAPI(); let exercise = TaskArchiveExercise(client:api,fixture:api,sleep:{_ in})
        let checkpoint = try await exercise.runBeforeRestart(); let result = try await exercise.runAfterRestart(checkpoint)
        func boot(_ index: Int, format: Bool? = nil, auth: TaskArchiveAuthenticationProof? = nil, stop: Bool = true) -> TaskArchiveBootReport {
            let audit = GuestBootLogAudit(diagnostics:[],credentialsAbsent:true,isolationWitnessesPresent:true,formatStageObserved:format ?? (index == 1),complete:true)
            return .init(index:index,reachedReady:true,authentication:auth ?? (index == 1 ? .freshSetup : .persistedSession),protectedStatus:401,cpuCount:1,cooperativeStop:stop,machineStopped:true,audit:audit)
        }
        let valid = [boot(1),boot(2),boot(3)]
        func passed(_ boots: [TaskArchiveBootReport], attempts: Int = 3, stage: TaskArchiveProbeStage = .complete, seeded: Bool = true, cpu: Int = 1, terminal: Bool = true) -> Bool {
            TaskArchiveRunReport(stage:stage,bootAttempts:attempts,expectedCPUCount:cpu,boots:boots,seedConfirmed:seeded,exercise:result,terminalSuccess:terminal,machineStopped:true).passed
        }
        XCTAssertTrue(passed(valid)); XCTAssertFalse(passed(Array(valid.prefix(2))))
        XCTAssertFalse(passed([boot(1),boot(2,format:true),boot(3)])); XCTAssertFalse(passed([boot(1),boot(2,auth:.freshSetup),boot(3)]))
        XCTAssertFalse(passed([boot(1),boot(2),boot(3,stop:false)])); XCTAssertFalse(passed(valid,attempts:4))
        XCTAssertFalse(passed(valid,stage:.shutdown)); XCTAssertFalse(passed(valid,seeded:false)); XCTAssertFalse(passed(valid,cpu:2)); XCTAssertFalse(passed(valid,terminal:false))
    }

}
