import Foundation

/// Implemented by a developer-only adapter running fixed audit code inside the guest.
@MainActor public protocol FindingFixtureControlling {
    func verifyNoAgentActivity() async throws
}
public struct FindingExerciseCheckpoint: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let initialChecks: [String]
    public let mutation: FindingExerciseMutationProof
    public let terminalChecks: [String]
    public let beforeRequestCount: Int
}
/// Finite API assertions only. Actual VM boot, same-disk restart and stopped-log acceptance belongs to the probe.
public struct FindingExerciseReport: Encodable, Equatable, Sendable {
    public let checkpoint: FindingExerciseCheckpoint
    public let finalChecks: [String]
    public let afterRequestCount: Int
    public let passed: Bool
}
@MainActor public final class FindingExercise {
    private let client: any BackendJSONTransport
    private let fixture: any FindingFixtureControlling
    private let now: @MainActor () -> ContinuousClock.Instant
    private var started = false
    private static let terminalChecks = ["post_mutation_stats","post_mutation_asset_tree"]
    public init(client: any BackendJSONTransport,fixture: any FindingFixtureControlling,
                now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock().now }) {
        self.client = client; self.fixture = fixture; self.now = now
    }
    public func runBeforeRestart() async throws -> FindingExerciseCheckpoint {
        let gate = try begin(); try await audit(gate)
        let initial = try await FindingExerciseReadChecks(client:gate).runInitial()
        guard initial == FindingExerciseReadChecks.expectedChecks(persisted:false) else { throw failure() }
        try await audit(gate)
        let mutation = try await FindingExerciseMutationChecks(client:gate).run()
        guard valid(mutation) else { throw failure() }
        let service = FindingService(client:gate), rows = FindingExerciseFixture.persisted
        try FindingExerciseAggregateVerifier.stats(try await service.stats(),rows:rows)
        try FindingExerciseAggregateVerifier.tree(try await service.assetTree(),rows:rows)
        try await audit(gate)
        guard gate.requestCount == 116 else { throw failure() }
        return .init(schemaVersion:1,initialChecks:initial,mutation:mutation,terminalChecks:Self.terminalChecks,beforeRequestCount:gate.requestCount)
    }
    public func runAfterRestart(_ checkpoint: FindingExerciseCheckpoint) async throws -> FindingExerciseReport {
        let gate = try begin()
        guard checkpoint.schemaVersion == 1, checkpoint.beforeRequestCount == 116,
              checkpoint.initialChecks == FindingExerciseReadChecks.expectedChecks(persisted:false), valid(checkpoint.mutation),
              checkpoint.terminalChecks == Self.terminalChecks else { throw failure() }
        try await audit(gate)
        let checks = try await FindingExerciseReadChecks(client:gate).runPersisted()
        guard checks == FindingExerciseReadChecks.expectedChecks(persisted:true) else { throw failure() }
        try await audit(gate)
        guard gate.requestCount == 100 else { throw failure() }
        return .init(checkpoint:checkpoint,finalChecks:checks,afterRequestCount:gate.requestCount,passed:true)
    }
    private func begin() throws -> FindingExerciseTransport {
        guard !started else { throw failure() }; started = true
        return try FindingExerciseTransport(client:client,now:now)
    }
    private func audit(_ gate: FindingExerciseTransport) async throws {
        try gate.checkLifecycle(); try await fixture.verifyNoAgentActivity(); try gate.checkLifecycle()
    }
    private func valid(_ proof: FindingExerciseMutationProof) -> Bool {
        proof.checks == FindingExerciseMutationChecks.expectedChecks && proof.requestCount == 14 && proof.partialHTTPStatus == 500
    }
    private func failure() -> RuntimeError { .integrity("findings exercise checkpoint mismatch") }
}
