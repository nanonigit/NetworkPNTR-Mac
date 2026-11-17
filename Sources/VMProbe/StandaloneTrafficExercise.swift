#if DEBUG
import NetworkPNTRCore
import Foundation

/// Fixed diagnostic fixture only. This exercises Core services/stores, not native input controls.
@MainActor enum StandaloneTrafficExercise {
    struct Result {
        let receipt: FindingTraffic
        let pageCounts: [Int]
        let sourceOrdinals = [3, 4]
        let crossPageSelectionChecked: Bool
        let replayBlocked: Bool
        let selectionCleared: Bool
        var report: [String: Any] {
            ["pageCounts": pageCounts, "sourceOrdinals": sourceOrdinals,
             "crossPageSelectionChecked": crossPageSelectionChecked, "replayBlocked": replayBlocked,
             "selectionCleared": selectionCleared, "bindingVersion": receipt.version,
             "bindingCount": receipt.bindings.count, "nativeUIAcceptance": false]
        }
    }
    static func run(client: any BackendJSONTransport, records: [CapturedTrafficExchange]) async throws -> Result {
        try require(records.count == 29 && Set(records.map(\.identity)).count == 29)
        for (index, row) in records.enumerated() { try require(try CapturedProbeContract.ordinal(row.url) == index) }
        let store = TrafficStore(service: TrafficService(client: client))
        let binding = TrafficBindingStore(service: FindingTrafficService(client: client))
        defer { store.stop(); binding.stop() }
        var query = TrafficQuery(); query.size = 25
        var paged: [CapturedTrafficExchange] = [], counts: [Int] = []
        for page in 0...1 {
            query.page = Int64(page)
            try require(store.configure(query, owner: store.owner)); await store.refresh()
            guard let value = store.catalog.value else { throw failure() }
            try require(!store.catalog.isStale && !store.hosts.isStale && !store.settings.isStale && !value.isUnavailable
                && value.count == 29 && value.total == 29 && value.exchanges.count == (page == 0 ? 25 : 4))
            counts.append(value.exchanges.count); paged += value.exchanges
            guard let first = value.exchanges.first else { throw failure() }
            try require(store.toggleFlow(id: first.id, selected: true, owner: store.owner))
        }
        try require(store.selectedFlowIDs.count == 2 && Set(paged.map(\.identity)) == Set(records.map(\.identity)) && paged.count == 29)
        let originals = Dictionary(uniqueKeysWithValues: records.map { ($0.identity, $0) })
        for row in paged {
            guard let expected = originals[row.identity] else { throw failure() }
            try require(same(row, expected))
        }
        try require(store.clearFlowSelection(owner: store.owner) && store.selectedFlowIDs.isEmpty)
        for index in [3, 4] {
            guard let position = paged.firstIndex(where: { $0.identity == records[index].identity }) else { throw failure() }
            query.page = Int64(position / 25)
            try require(store.configure(query, owner: store.owner)); await store.refresh()
            try require(store.toggleFlow(id: records[index].id, selected: true, owner: store.owner))
        }
        let sources = store.selectedFlowIDs, owner = store.owner, revision = store.flowRevision
        try require(sources.map { Data($0.utf8) } == [records[3].identity, records[4].identity])
        var target: FindingRecord?
        let findings = FindingService(client: client)
        for page in 1...2 {
            let candidates = try await findings.bindingCandidates(search: "", page: Int64(page))
            if let match = candidates.items.first(where: { $0.findingId == "9101" }) { target = match; break }
        }
        guard let target, target.canMutate else { throw failure() }
        try require(binding.select(target, sourceIDs: sources, owner: binding.owner))
        await binding.refresh(owner: binding.owner)
        try require(binding.canBind && binding.summary?.bindings.isEmpty == true)
        let request = binding.requestID, bindingOwner = binding.owner
        let outcome = await binding.bind(id: request, owner: bindingOwner) {
            try require(store.owner == owner && store.flowRevision == revision && store.isActive)
        }
        guard case .confirmed(let receipt) = outcome else { throw failure() }
        try require(receipt.bindings.count == 2)
        for (row, index) in zip(receipt.bindings, [3, 4]) {
            try require(Data(row.snapshot.sourceTrafficId.utf8) == records[index].identity
                && Data(row.snapshot.url.utf8) == Data(records[index].url.utf8)
                && row.role == "supporting" && row.note.isEmpty)
        }
        guard case .notStarted = await binding.bind(id: request, owner: bindingOwner) else { throw failure() }
        try require(store.owner == owner && store.flowRevision == revision)
        try require(store.clearFlowSelection(owner: owner) && store.selectedFlowIDs.isEmpty)
        return .init(receipt: receipt, pageCounts: counts, crossPageSelectionChecked: true, replayBlocked: true, selectionCleared: true)
    }
    private static func same(_ left: CapturedTrafficExchange, _ right: CapturedTrafficExchange) -> Bool {
        [left.id, left.ts, left.host, left.url, left.method, left.contentType].map { Data($0.utf8) }
            == [right.id, right.ts, right.host, right.url, right.method, right.contentType].map { Data($0.utf8) }
            && left.status == right.status && left.responseLength == right.responseLength
    }
    private static func require(_ value: Bool) throws { guard value else { throw failure() } }
    private static func failure() -> RuntimeError { .integrity("standalone traffic fixed exercise") }
}
#endif
