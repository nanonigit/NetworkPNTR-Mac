import Foundation

public struct FindingExerciseMutationProof: Codable, Equatable, Sendable {
    public let checks: [String]
    public let partialHTTPStatus: Int
    public let requestCount: Int
}

/// Fixed diagnostic findings only. A failed PATCH is read back and explicitly acknowledged, never retried.
@MainActor final class FindingExerciseMutationChecks {
    static let expectedChecks = ["initial_cache","edited_fields","separate_status","partial_patch_http500",
        "partial_patch_readback","uncertainty_retained_after_read","uncertainty_blocks_write","explicit_acknowledgment",
        "final_status","delete_9102","delete_9133","final_cache"]
    private let gate: FindingExerciseTransport
    private let service: FindingService
    private let store: FindingStore
    private var started = false
    init(client: any BackendJSONTransport) throws {
        let gate = try FindingExerciseTransport(client:client)
        self.gate = gate; service = FindingService(client:gate); store = FindingStore(service:service)
    }
    func run() async throws -> FindingExerciseMutationProof {
        guard !started else { throw failure() }; started = true
        try Task.checkCancellation()
        guard await store.refreshView(), let page = store.flat.read.value else { throw failure() }
        try FindingExerciseVerifier.page(page,vector:FindingExerciseFixture.vectors(rows:FindingExerciseFixture.initial)[0],rows:FindingExerciseFixture.initial)
        var checks = [Self.expectedChecks[0]], expected = FindingExerciseFixture.initial[0]
        await store.select(id:"9101",owner:store.viewOwner)
        try Task.checkCancellation(); try FindingExerciseVerifier.detail(detail(),expected:expected)
        let edited = try updated(await store.update(detail(),patch:.init(name:FindingExerciseFixture.editedName,
            vulnclass:FindingExerciseFixture.editedClass,severity:.low),owner:store.viewOwner))
        expected.name = FindingExerciseFixture.editedName; expected.vulnclass = FindingExerciseFixture.editedClass; expected.severity = .low
        try FindingExerciseVerifier.detail(edited,expected:expected); try verifyCachedEdit(expected)
        checks.append(Self.expectedChecks[1])
        let confirmed = try updated(await store.update(detail(),patch:.init(status:.confirmed),owner:store.viewOwner))
        expected.status = .confirmed; try FindingExerciseVerifier.detail(confirmed,expected:expected)
        try verifyCachedEdit(expected); checks.append(Self.expectedChecks[2])
        let outcome = await store.update(try detail(),patch:.init(name:FindingExerciseFixture.failingName,status:.riskAccepted),owner:store.viewOwner)
        try Task.checkCancellation()
        guard case .unconfirmed = outcome, gate.lastMutationStatus == 500, store.unknownIDs == ["9101"],
              !store.isMutating, store.mutationFailure != nil else { throw failure() }
        if case .some = store.lastConfirmation { throw failure() }
        try FindingExerciseVerifier.detail(detail(),expected:expected)
        let partialHTTP = gate.lastMutationStatus!, session = store.sessionOwner, revision = store.unknownRevision
        checks.append(Self.expectedChecks[3])
        let actual = try await service.detail(id:"9101")
        expected.status = .riskAccepted; try FindingExerciseVerifier.detail(actual,expected:expected)
        checks.append(Self.expectedChecks[4])
        await store.refreshSelected(); try Task.checkCancellation()
        guard !store.detail.isStale, store.unknownIDs == ["9101"], store.unknownRevision == revision else { throw failure() }
        try FindingExerciseVerifier.detail(detail(),expected:expected); checks.append(Self.expectedChecks[5])
        let count = gate.requestCount
        guard case .notStarted = await store.update(actual,patch:.init(status:.fixed),owner:store.viewOwner),
              gate.requestCount == count else { throw failure() }
        checks.append(Self.expectedChecks[6])
        guard store.acknowledgeUnknown("9101",owner:session,revision:revision), store.unknownIDs.isEmpty,
              !store.acknowledgeUnknown("9101",owner:session,revision:revision) else { throw failure() }
        checks.append(Self.expectedChecks[7])
        let fixed = try updated(await store.update(detail(),patch:.init(status:.fixed),owner:store.viewOwner))
        expected.status = .fixed; try FindingExerciseVerifier.detail(fixed,expected:expected); try verifyCachedEdit(expected)
        checks.append(Self.expectedChecks[8])
        for id in ["9102","9133"] { store.setSelected(id,selected:true,owner:store.viewOwner) }
        guard store.selectedIDs == ["9102","9133"] else { throw failure() }
        for id in ["9102","9133"] {
            await store.select(id:id,owner:store.viewOwner); try Task.checkCancellation()
            guard let original = FindingExerciseFixture.initial.first(where:{$0.id == id}) else { throw failure() }
            try FindingExerciseVerifier.detail(detail(),expected:original)
            let deletion = await store.delete(try detail(),owner:store.viewOwner); try Task.checkCancellation()
            guard case .confirmed(.deleted(let receipt)) = deletion, String(receipt.id) == id, receipt.deleted,
                  store.selectedDetail == nil, store.detail.value == nil, !store.selectedIDs.contains(id),
                  store.flat.read.value?.items.contains(where:{$0.id == id}) == false else { throw failure() }
            do { _ = try await service.detail(id:id); throw failure() }
            catch BackendAPIError.status(404) { checks.append("delete_"+id) }
        }
        guard store.flat.read.value?.total == 31, store.flat.read.value?.items.count == 18, store.selectedIDs.isEmpty,
              store.unknownIDs.isEmpty, gate.requestCount == 14 else { throw failure() }
        try verifyCachedEdit(expected); checks.append(Self.expectedChecks[11]); try Task.checkCancellation()
        return .init(checks:checks,partialHTTPStatus:partialHTTP,requestCount:gate.requestCount)
    }
    private func updated(_ outcome: FindingMutationOutcome) throws -> FindingRecord {
        try Task.checkCancellation()
        guard case .confirmed(.updated(let row)) = outcome else { throw failure() }; return row
    }
    private func detail() throws -> FindingRecord {
        guard let value = store.detail.value, store.detail.failure == nil else { throw failure() }; return value
    }
    private func verifyCachedEdit(_ expected: FindingExerciseFixture.Row) throws {
        guard let row = store.flat.read.value?.items.first(where:{$0.id == "9101"}) else { throw failure() }
        try FindingExerciseVerifier.detail(row,expected:expected)
    }
    private func failure() -> RuntimeError { .integrity("findings mutation exercise mismatch") }
}
