import Foundation

public struct TaskArchiveFixtureTarget: Sendable {
    public let archiveID: Int64
    public let sha256: String
}
/// Implemented only by a developer probe using fixed, authenticated guest fixture code.
@MainActor public protocol TaskArchiveFixtureControlling {
    func setPackageHidden(_ hidden: Bool, target: TaskArchiveFixtureTarget) async throws
    func verifyNoAgentActivity() async throws
}
public struct TaskArchiveFileProof: Codable, Equatable, Sendable {
    public let path: String
    public let size: Int64
    public let sha256: String
}
public struct TaskArchiveCheckpoint: Codable, Sendable {
    public let archiveID: Int64
    public let packageSHA256: String
    public let checks: [String]
    public let files: [TaskArchiveFileProof]
}
public struct TaskArchiveExerciseReport: Encodable, Equatable, Sendable {
    public let checks: [String]
    public let files: [TaskArchiveFileProof]
    public let taskName: String
    public let taskDescription: String
    public let passed: Bool
}

/// Fixed terminal fixtures only. Never calls task creation, resume, chat or a host command.
@MainActor public final class TaskArchiveExercise {
    public struct File: Sendable { public let taskID: Int64; public let path: String; public let data: Data }
    public static let name = "\u{feff}e\u{301} 中文 한국어"
    public static let description = "Archive fixture e\u{301} \u{feff} interior 中文 한국어"
    public static let goal = "Synthetic terminal archive fixture; no agent execution"
    public static let files: [File] = [
        .init(taskID:7101,path:"tasks/7101/workspace/fixture-e\u{301}.txt",data:Data("Archive bytes \u{feff} e\u{301} 日本語\n".utf8)),
        .init(taskID:7101,path:"tasks/7101/workspace/empty.bin",data:Data()),
        .init(taskID:7102,path:"tasks/7102/workspace/fixture.bin",data:Data((0..<1024).map{UInt8($0 % 256)}))
    ]
    public static let beforeRestartChecks = ["initial_terminal_tasks","initial_workspace_bytes","bulk_archive_accepted","bulk_archive_ready","live_rows_removed","workspace_files_removed","restore_failure_observed","explicit_retry_accepted","first_task_restored","first_workspace_restored","second_delete_accepted","second_archive_removed","first_rearchive_accepted","first_ready_for_restart"]
    public static let expectedChecks = beforeRestartChecks + ["persisted_archive_ready","restart_restore_accepted","restart_task_restored","restart_workspace_restored","second_task_stays_deleted"]
    private let client: any BackendJSONTransport
    private let fixture: any TaskArchiveFixtureControlling
    private let archives: TaskArchiveService
    private let tasks: TaskService
    private let sleep: @MainActor (Duration) async throws -> Void
    private let now: @MainActor () -> ContinuousClock.Instant
    private let progress: @MainActor (String) -> Void
    public init(client: any BackendJSONTransport, fixture: any TaskArchiveFixtureControlling,
                sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for:$0) },
                now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock().now },
                progress: @escaping @MainActor (String) -> Void = { _ in }) {
        self.client = client; self.fixture = fixture; self.sleep = sleep; self.now = now; self.progress = progress
        archives = TaskArchiveService(client:client); tasks = TaskService(client:client)
    }
    public func runBeforeRestart() async throws -> TaskArchiveCheckpoint {
        try Task.checkCancellation(); progress("initial_terminal_tasks")
        try await fixture.verifyNoAgentActivity(); try Task.checkCancellation()
        try verifyLive(try await tasks.list(),expected:[7101,7102])
        guard try await archives.list().items.isEmpty else { throw failure("initial archive list") }
        var checks = [Self.beforeRestartChecks[0]]
        let proofs = try await verifyFiles(taskIDs:[7101,7102],present:true); checks.append(Self.beforeRestartChecks[1])
        progress("bulk_archive")
        let accepted = try await archives.queueBatch(taskIDs:["7102","7101"])
        guard accepted.count == 2, accepted.allSatisfy({$0.ok && $0.queued}),
              let firstID = accepted.first(where:{$0.id == "7101"})?.archiveId,
              let secondID = accepted.first(where:{$0.id == "7102"})?.archiveId else { throw failure("bulk receipt") }
        checks.append(Self.beforeRestartChecks[2])
        _ = try await waitState(id:firstID,task:7101,desired:"ready",waiting:["archive_queued","archiving"])
        _ = try await waitState(id:secondID,task:7102,desired:"ready",waiting:["archive_queued","archiving"])
        checks.append(Self.beforeRestartChecks[3])
        try await waitLive([]); checks.append(Self.beforeRestartChecks[4])
        _ = try await verifyFiles(taskIDs:[7101,7102],present:false); checks.append(Self.beforeRestartChecks[5])
        progress("restore_failure")
        let first = try await archives.detail(id:firstID); try verifyReady(first,task:7101)
        let target = TaskArchiveFixtureTarget(archiveID:firstID,sha256:first.sha256!)
        try Task.checkCancellation(); try await fixture.setPackageHidden(true,target:target); try Task.checkCancellation()
        _ = try await archives.restore(id:firstID)
        let failed = try await waitState(id:firstID,task:7101,desired:"restore_failed",waiting:["restore_queued","restoring"])
        guard failed.hasError else { throw failure("missing restore failure") }; checks.append(Self.beforeRestartChecks[6])
        try await fixture.setPackageHidden(false,target:target); try Task.checkCancellation()
        progress("explicit_retry")
        _ = try await archives.retry(failed); checks.append(Self.beforeRestartChecks[7])
        try await waitRemoved(id:firstID,task:7101,waiting:["restore_queued","restoring"])
        try await waitLive([7101]); try verifyTask(try await tasks.detail(id:"7101"),id:7101); checks.append(Self.beforeRestartChecks[8])
        _ = try await verifyFiles(taskIDs:[7101],present:true); checks.append(Self.beforeRestartChecks[9])
        progress("delete_second")
        try verifyReady(try await archives.detail(id:secondID),task:7102)
        _ = try await archives.delete(id:secondID); checks.append(Self.beforeRestartChecks[10])
        try await waitRemoved(id:secondID,task:7102,waiting:["delete_queued","deleting"])
        try await requireMissingTask("7102")
        try await requireMissingFile("archives/tasks/task-7102-\(secondID).tar.zst")
        checks.append(Self.beforeRestartChecks[11])
        progress("rearchive_first")
        let queued = try await archives.queue(taskID:"7101"); checks.append(Self.beforeRestartChecks[12])
        let ready = try await waitState(id:queued.id,task:7101,desired:"ready",waiting:["archive_queued","archiving"])
        try await waitLive([])
        let page = try await archives.list()
        guard page.items.count == 1, page.items[0].id == ready.id else { throw failure("restart archive set") }
        try verifyReady(page.items[0],task:7101)
        try await fixture.verifyNoAgentActivity(); try Task.checkCancellation()
        checks.append(Self.beforeRestartChecks[13]); progress("before_restart_complete")
        return .init(archiveID:ready.id,packageSHA256:ready.sha256!,checks:checks,files:proofs)
    }
    public func runAfterRestart(_ checkpoint: TaskArchiveCheckpoint) async throws -> TaskArchiveExerciseReport {
        try Task.checkCancellation()
        guard checkpoint.archiveID > 0, checkpoint.checks == Self.beforeRestartChecks,
              Self.validProofs(checkpoint.files), Self.validSHA(checkpoint.packageSHA256) else { throw failure("checkpoint") }
        progress("persisted_archive")
        try await fixture.verifyNoAgentActivity(); try Task.checkCancellation()
        try verifyLive(try await tasks.list(),expected:[])
        let page = try await archives.list()
        guard page.items.count == 1, page.items[0].id == checkpoint.archiveID else { throw failure("persisted archive set") }
        let ready = try await archives.detail(id:checkpoint.archiveID); try verifyReady(ready,task:7101)
        guard ready.sha256 == checkpoint.packageSHA256 else { throw failure("persisted archive digest") }
        var checks = checkpoint.checks + [Self.expectedChecks[14]]
        _ = try await archives.restore(id:ready.id); checks.append(Self.expectedChecks[15])
        try await waitRemoved(id:ready.id,task:7101,waiting:["restore_queued","restoring"])
        try await waitLive([7101]); let restored = try await tasks.detail(id:"7101"); try verifyTask(restored,id:7101)
        checks.append(Self.expectedChecks[16])
        _ = try await verifyFiles(taskIDs:[7101],present:true); checks.append(Self.expectedChecks[17])
        try await requireMissingTask("7102"); _ = try await verifyFiles(taskIDs:[7102],present:false)
        guard try await archives.list().items.isEmpty else { throw failure("final archive set") }
        try await fixture.verifyNoAgentActivity(); try Task.checkCancellation()
        checks.append(Self.expectedChecks[18]); progress("archive_exercise_complete")
        return .init(checks:checks,files:checkpoint.files,taskName:restored.name,taskDescription:restored.description,
                     passed:checks == Self.expectedChecks && Self.validProofs(checkpoint.files))
    }
    private func verifyTask(_ row: TaskRecord, id: Int64) throws {
        guard row.id == String(id), row.explorationId == id, row.status == "done", !row.paused, !row.queued, row.inFlight == 0,
              row.llmProfileId == nil, row.activeLlmProfileId == nil, row.llmProfileIds.isEmpty, row.sourceTaskIds.isEmpty,
              row.categoryId == 7100, row.categoryName == "T17 archive category", same(row.name,id == 7101 ? Self.name : "T17 second"),
              same(row.description,id == 7101 ? Self.description : "Archive fixture second"), same(row.goal,Self.goal) else { throw failure("terminal task metadata") }
    }
    private func verifyLive(_ snapshot: TaskListSnapshot, expected: Set<Int64>) throws {
        guard Set(snapshot.tasks.map(\.id)) == Set(expected.map(String.init)),
              snapshot.activeID.map({expected.contains(Int64($0) ?? 0)}) ?? true else { throw failure("live task set") }
        for row in snapshot.tasks { try verifyTask(row,id:Int64(row.id)!) }
    }
    private func verifyReady(_ row: TaskArchiveRecord, task: Int64) throws {
        guard row.taskId == task, row.state == "ready", row.progress == 100, row.originalStatus == "done", !row.hasError,
              row.warningCount == 0, row.originalSize > 0, row.compressedSize > 0, row.sha256.map(Self.validSHA) ?? false,
              row.dataCounts["tasks"] == 1, row.dataCounts["explorations"] == 1,
              row.categoryId == 7100, row.categoryName == "T17 archive category", same(row.taskName,task == 7101 ? Self.name : "T17 second"),
              same(row.taskDescription,task == 7101 ? Self.description : "Archive fixture second"), same(row.taskGoal,Self.goal) else { throw failure("ready archive metadata") }
    }
    private func waitState(id: Int64, task: Int64, desired: String, waiting: Set<String>) async throws -> TaskArchiveRecord {
        let deadline = now().advanced(by:.seconds(45))
        for attempt in 0..<120 {
            try check(deadline)
            let row = try await archives.detail(id:id); try check(deadline)
            guard row.taskId == task else { throw failure("archive owner") }
            if row.state == desired { if desired == "ready" { try verifyReady(row,task:task) }; return row }
            guard waiting.contains(row.state) else { throw failure("archive terminal state") }
            if attempt < 119 { try await sleep(.milliseconds(200)) }
        }
        throw failure("archive polling limit")
    }
    private func waitRemoved(id: Int64, task: Int64, waiting: Set<String>) async throws {
        let deadline = now().advanced(by:.seconds(45))
        for attempt in 0..<120 {
            try check(deadline)
            do {
                let row = try await archives.detail(id:id); try check(deadline)
                guard row.taskId == task, waiting.contains(row.state) else { throw failure("archive removal state") }
            } catch BackendAPIError.status(404) { try check(deadline); return }
            if attempt < 119 { try await sleep(.milliseconds(200)) }
        }
        throw failure("archive removal polling limit")
    }
    private func waitLive(_ expected: Set<Int64>) async throws {
        let deadline = now().advanced(by:.seconds(45))
        for attempt in 0..<120 {
            try check(deadline)
            let snapshot = try await tasks.list(); try check(deadline)
            let ids = Set(snapshot.tasks.map(\.id))
            guard ids.isSubset(of:["7101","7102"]) else { throw failure("foreign live tasks") }
            if ids == Set(expected.map(String.init)) { try verifyLive(snapshot,expected:expected); return }
            if attempt < 119 { try await sleep(.milliseconds(200)) }
        }
        throw failure("live task polling limit")
    }
    private func verifyFiles(taskIDs: Set<Int64>, present: Bool) async throws -> [TaskArchiveFileProof] {
        var proof: [TaskArchiveFileProof] = []
        for file in Self.files where taskIDs.contains(file.taskID) {
            let response = try await workspace(file.path)
            guard present ? response.status == 200 && response.body == file.data : response.status == 404 else { throw failure("workspace bytes") }
            if present { proof.append(.init(path:file.path,size:Int64(file.data.count),sha256:ArtifactIntegrity.sha256(response.body))) }
        }
        return proof
    }
    private func requireMissingFile(_ path: String) async throws {
        guard try await workspace(path).status == 404 else { throw failure("deleted package still present") }
    }
    private func requireMissingTask(_ id: String) async throws {
        do { _ = try await tasks.detail(id:id); throw failure("deleted task still present") } catch BackendAPIError.status(404) {}
    }
    private func workspace(_ path: String) async throws -> BackendHTTPResponse {
        var query = URLComponents(); query.queryItems = [.init(name:"path",value:path)]
        guard let encoded = query.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%2B") else { throw failure("workspace path") }
        try Task.checkCancellation(); let response = try await client.send(method:"GET",path:"/api/workspace/download?"+encoded,body:nil,bearer:nil)
        try Task.checkCancellation(); return response
    }
    private static func validProofs(_ proof: [TaskArchiveFileProof]) -> Bool {
        proof.count == files.count && zip(proof,files).allSatisfy { p,f in p.path.utf8.elementsEqual(f.path.utf8) && p.size == Int64(f.data.count) && p.sha256 == ArtifactIntegrity.sha256(f.data) }
    }
    private static func validSHA(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy{(48...57).contains($0) || (97...102).contains($0)} }
    private func same(_ a: String,_ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    private func check(_ deadline: ContinuousClock.Instant) throws { try Task.checkCancellation(); guard now() <= deadline else { throw failure("stage deadline") } }
    private func failure(_ stage: String) -> RuntimeError { .integrity("archive exercise "+stage) }
}
