import XCTest
@testable import ArtexCore

@MainActor private final class FindingExerciseAuditor: FindingFixtureControlling {
    var calls = 0
    var failAt: Int?
    var onAudit: (() -> Void)?
    func verifyNoAgentActivity() async throws {
        calls += 1; onAudit?()
        if calls == failAt { throw BackendAPIError.invalidResponse }
    }
}
@MainActor private final class FindingExerciseClock {
    var instant = ContinuousClock().now
}
@MainActor private final class FindingExerciseCombinedWire: BackendJSONTransport {
    let initial: FindingReadExerciseWire
    let mutation: FindingMutationExerciseWire
    let final: FindingReadExerciseWire
    var calls = 0
    init() throws {
        initial = try FindingReadExerciseWire(); mutation = try FindingMutationExerciseWire()
        final = try FindingReadExerciseWire(persisted:true)
    }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls += 1
        if calls <= 100 { return try await initial.send(method:method,path:path,body:body,bearer:bearer) }
        if calls <= 114 { return try await mutation.send(method:method,path:path,body:body,bearer:bearer) }
        XCTAssertEqual(mutation.rows.count,31)
        return try await final.send(method:method,path:path,body:body,bearer:bearer)
    }
}
final class FindingExerciseTests: XCTestCase {
    @MainActor private func checkpoint() async throws -> FindingExerciseCheckpoint {
        try await FindingExercise(client:FindingExerciseCombinedWire(),fixture:FindingExerciseAuditor()).runBeforeRestart()
    }
    @MainActor func testAuditedBeforeAndAfterStagesHaveOneSharedBudgetAndCompleteTypedCheckpoint() async throws {
        let wire = try FindingExerciseCombinedWire(), audit = FindingExerciseAuditor()
        let before = FindingExercise(client:wire,fixture:audit)
        let checkpoint = try await before.runBeforeRestart()
        XCTAssertEqual(wire.calls,116); XCTAssertEqual(checkpoint.beforeRequestCount,116); XCTAssertEqual(audit.calls,3)
        XCTAssertEqual(checkpoint.initialChecks.count,100); XCTAssertEqual(checkpoint.mutation.requestCount,14)
        do { _ = try await before.runBeforeRestart(); XCTFail("Exercise replay accepted") } catch { }
        XCTAssertEqual(wire.calls,116)
        let restart = try FindingReadExerciseWire(persisted:true), afterAudit = FindingExerciseAuditor()
        let after = FindingExercise(client:restart,fixture:afterAudit)
        let report = try await after.runAfterRestart(checkpoint)
        XCTAssertTrue(report.passed); XCTAssertEqual(report.afterRequestCount,100); XCTAssertEqual(afterAudit.calls,2)
        XCTAssertEqual(report.finalChecks.count,100); XCTAssertEqual(restart.calls.count,100)
        do { _ = try await after.runAfterRestart(checkpoint); XCTFail("Persisted stage replay accepted") } catch { }
        XCTAssertEqual(afterAudit.calls,2)
    }
    @MainActor func testTamperedCheckpointFailsBeforeAuditOrNetwork() async throws {
        let checkpoint = try await checkpoint()
        let encoded = try JSONEncoder().encode(checkpoint)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        for field in ["schemaVersion","beforeRequestCount","initialChecks","mutation","terminalChecks"] {
            var changed = object
            switch field {
            case "initialChecks","terminalChecks": changed[field] = ["forged"]
            case "mutation": changed[field] = ["checks":["forged"],"partialHTTPStatus":500,"requestCount":14] as [String:Any]
            default: changed[field] = 999
            }
            let invalid = try JSONDecoder().decode(FindingExerciseCheckpoint.self,from:JSONSerialization.data(withJSONObject:changed))
            let wire = try FindingReadExerciseWire(persisted:true), audit = FindingExerciseAuditor()
            do { _ = try await FindingExercise(client:wire,fixture:audit).runAfterRestart(invalid); XCTFail(field) } catch { }
            XCTAssertTrue(wire.calls.isEmpty,field); XCTAssertEqual(audit.calls,0,field)
        }
    }
    @MainActor func testFailedAuditStopsBeforeAnyLaterOperation() async throws {
        for index in [1,2,3] {
            let wire = try FindingExerciseCombinedWire(), audit = FindingExerciseAuditor(); audit.failAt = index
            do { _ = try await FindingExercise(client:wire,fixture:audit).runBeforeRestart(); XCTFail("Audit failure accepted") } catch { }
            XCTAssertEqual(wire.calls,index == 1 ? 0 : (index == 2 ? 100 : 116))
            XCTAssertEqual(audit.calls,index)
        }
    }
    @MainActor func testAuditDeadlineAndCancellationCannotReturnSuccessfulCheckpoint() async throws {
        let clock = FindingExerciseClock(), wire = try FindingExerciseCombinedWire(), audit = FindingExerciseAuditor()
        audit.onAudit = { clock.instant = clock.instant.advanced(by:.seconds(91)) }
        do { _ = try await FindingExercise(client:wire,fixture:audit,now:{clock.instant}).runBeforeRestart(); XCTFail("Late audit accepted") } catch { }
        XCTAssertEqual(wire.calls,0)
        let canceledWire = try FindingExerciseCombinedWire(), canceledAudit = FindingExerciseAuditor()
        let exercise = FindingExercise(client:canceledWire,fixture:canceledAudit)
        let task = Task { try await exercise.runBeforeRestart() }; canceledAudit.onAudit = { task.cancel() }
        do { _ = try await task.value; XCTFail("Canceled audit accepted") } catch is CancellationError { }
        XCTAssertEqual(canceledWire.calls,0)
    }
}
