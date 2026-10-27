import Foundation

/// Read-only part of the developer experiment. These checks alone are not a runtime acceptance report.
@MainActor final class FindingExerciseReadChecks {
    private let service: FindingService
    private var started = false
    init(client: any BackendJSONTransport) throws {
        service = FindingService(client:try FindingExerciseTransport(client:client))
    }
    func runInitial() async throws -> [String] {
        guard !started else { throw RuntimeError.integrity("findings read stage already started") }
        started = true
        try Task.checkCancellation()
        let rows = FindingExerciseFixture.initial
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
        try Task.checkCancellation()
        return checks
    }
}
