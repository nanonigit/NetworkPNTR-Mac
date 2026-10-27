import Foundation

/// Read-only part of the developer experiment. These checks alone are not a runtime acceptance report.
@MainActor final class FindingExerciseReadChecks {
    private let service: FindingService
    private var started = false
    init(client: any BackendJSONTransport) throws {
        service = FindingService(client:try FindingExerciseTransport(client:client))
    }
    static func expectedChecks(persisted: Bool) -> [String] {
        let rows = persisted ? FindingExerciseFixture.persisted : FindingExerciseFixture.initial
        var names = FindingExerciseFixture.vectors(rows:rows).map(\.name) + rows.map{"detail_"+$0.id} + ["stats"]
        for sort in [FindingSort.severity,.time] {
            for page in 1...(sort == .severity ? 3 : 2) { names.append("groups_\(sort.rawValue)_\(page)") }
        }
        names += (1...3).map{"expanded_8101_\($0)"} + ["asset_tree"]
        names += FindingExerciseFixture.tasks.map{"nodes_"+$0}
        names += ["context_8101","context_8111","unrelated_context_rejected"]
        if persisted { names += ["deleted_9102","deleted_9133"] }; return names
    }
    func runInitial() async throws -> [String] {
        try await run(rows:FindingExerciseFixture.initial,deleted:[])
    }
    func runPersisted() async throws -> [String] {
        try await run(rows:FindingExerciseFixture.persisted,deleted:["9102","9133"])
    }
    private func run(rows: [FindingExerciseFixture.Row],deleted: [String]) async throws -> [String] {
        guard !started else { throw RuntimeError.integrity("findings read stage already started") }
        started = true
        try Task.checkCancellation()
        var checks: [String] = []
        for vector in FindingExerciseFixture.vectors(rows:rows) {
            let page = try await service.list(vector.query)
            try FindingExerciseVerifier.page(page,vector:vector,rows:rows)
            checks.append(vector.name)
        }
        for row in rows {
            let detail = try await service.detail(id:row.id)
            try FindingExerciseVerifier.detail(detail,expected:row)
            checks.append("detail_"+row.id)
        }
        try FindingExerciseAggregateVerifier.stats(try await service.stats(),rows:rows); checks.append("stats")
        for sort in [FindingSort.severity,.time] {
            for page in 1...(sort == .severity ? 3 : 2) {
                let query = FindingQuery(page:Int64(page),size:10,sort:sort)
                try FindingExerciseAggregateVerifier.groups(try await service.groups(query),query:query,rows:rows)
                checks.append("groups_\(sort.rawValue)_\(page)")
            }
        }
        for page in 1...3 {
            let query = FindingQuery(page:Int64(page),task:"8101")
            let found = FindingExerciseFixture.matching(rows,query:query)
            let ids = Array(found.dropFirst((page-1)*20).prefix(20)).map(\.id)
            let vector = FindingExerciseFixture.Vector(name:"expanded_8101_\(page)",query:query,ids:ids,total:Int64(found.count))
            try FindingExerciseVerifier.page(try await service.list(query),vector:vector,rows:rows)
            checks.append(vector.name)
        }
        try FindingExerciseAggregateVerifier.tree(try await service.assetTree(),rows:rows); checks.append("asset_tree")
        for task in FindingExerciseFixture.tasks {
            try FindingExerciseVerifier.task(try await service.forTask(id:task),id:task,rows:rows)
            checks.append("nodes_"+task)
        }
        guard let first = rows.first(where:{$0.id == "9101"}) else { throw RuntimeError.integrity("findings read fixture") }
        for context in ["8101","8111"] {
            try FindingExerciseVerifier.contextualDetail(try await service.detail(id:"9101",contextTaskID:context),expected:first,taskID:context)
            checks.append("context_"+context)
        }
        do {
            _ = try await service.detail(id:"9101",contextTaskID:"8102")
            throw RuntimeError.integrity("unrelated finding context accepted")
        } catch BackendAPIError.status(404) { checks.append("unrelated_context_rejected") }
        for id in deleted {
            do {
                _ = try await service.detail(id:id)
                throw RuntimeError.integrity("deleted finding still present")
            } catch BackendAPIError.status(404) { checks.append("deleted_"+id) }
        }
        try Task.checkCancellation()
        return checks
    }
}
