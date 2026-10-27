import Foundation

public struct FindingExerciseBoundaryProof: Codable, Equatable, Sendable {
    public let sharedChecks: [String]
    public let localChecks: [String]
    public let diagnosticFieldBytes: Int
    public let requestCount: Int
}

/// Deliberate fixture values, never inferred from the API response or reused as general text normalization.
enum FindingExerciseBoundaryFixture {
    static let name = "F4 boundary \u{feff}e\u{301} 中文 한국어"
    static let vulnclass = "F4 boundary class e\u{301} \u{feff} interior 中文 한국어"
    static let paddedName = "\u{feff} \u{85} "+name+" \u{85} \u{feff}"
    static let paddedClass = "\u{85} "+vulnclass+" \u{85}"
    static let longClass = String(repeating:"界",count:2730)+"AB"
}

/// Diagnostic field cap is8192 bytes, not a claim about the upstream/product text-field maximum.
@MainActor final class FindingExerciseBoundaryChecks {
    static let sharedChecks = ["single_name_normalized","single_class_normalized","single_severity","empty_name",
                               "diagnostic_class_8192_bytes","original_fields_restored"]
    static let localChecks = ["empty_patch_rejected","oversized_body_rejected","invalid_page_rejected"]
    private let gate: FindingExerciseTransport
    private let service: FindingService
    private let progress: @MainActor (String) -> Void
    private var started = false
    init(client: any BackendJSONTransport,progress: @escaping @MainActor (String) -> Void = { _ in }) throws {
        let gate = try FindingExerciseTransport(client:client)
        self.gate = gate; service = FindingService(client:gate); self.progress = progress
    }
    func run() async throws -> FindingExerciseBoundaryProof {
        guard !started else { throw failure() }; started = true; try Task.checkCancellation()
        progress("boundary_initial_detail")
        var actual = try await service.detail(id:"9101"), expected = FindingExerciseFixture.initial[0]
        try FindingExerciseVerifier.detail(actual,expected:expected)
        let count = gate.requestCount
        var local: [String] = []
        do { _ = try await service.update(actual,patch:.init()); throw failure() }
        catch FindingInputError.patch { local.append(Self.localChecks[0]) }
        do { _ = try await service.update(actual,patch:.init(name:String(repeating:"x",count:65536))); throw failure() }
        catch FindingInputError.bodyLimit { local.append(Self.localChecks[1]) }
        do { _ = try await service.list(.init(size:0)); throw failure() }
        catch FindingInputError.query { local.append(Self.localChecks[2]) }
        guard gate.requestCount == count else { throw failure() }; try Task.checkCancellation()
        var shared: [String] = []
        progress("boundary_"+Self.sharedChecks[0])
        actual = try await service.update(actual,patch:.init(name:FindingExerciseBoundaryFixture.paddedName))
        expected.name = FindingExerciseBoundaryFixture.name; try FindingExerciseVerifier.detail(actual,expected:expected)
        shared.append(Self.sharedChecks[0])
        progress("boundary_"+Self.sharedChecks[1])
        actual = try await service.update(actual,patch:.init(vulnclass:FindingExerciseBoundaryFixture.paddedClass))
        expected.vulnclass = FindingExerciseBoundaryFixture.vulnclass; try FindingExerciseVerifier.detail(actual,expected:expected)
        shared.append(Self.sharedChecks[1])
        progress("boundary_"+Self.sharedChecks[2])
        actual = try await service.update(actual,patch:.init(severity:.medium))
        expected.severity = .medium; try FindingExerciseVerifier.detail(actual,expected:expected); shared.append(Self.sharedChecks[2])
        progress("boundary_"+Self.sharedChecks[3])
        actual = try await service.update(actual,patch:.init(name:"\u{feff} \t"))
        expected.name = ""; try FindingExerciseVerifier.detail(actual,expected:expected); shared.append(Self.sharedChecks[3])
        progress("boundary_"+Self.sharedChecks[4])
        guard FindingExerciseBoundaryFixture.longClass.utf8.count == 8192 else { throw failure() }
        actual = try await service.update(actual,patch:.init(vulnclass:FindingExerciseBoundaryFixture.longClass))
        expected.vulnclass = FindingExerciseBoundaryFixture.longClass; try FindingExerciseVerifier.detail(actual,expected:expected)
        shared.append(Self.sharedChecks[4])
        progress("boundary_"+Self.sharedChecks[5])
        expected = FindingExerciseFixture.initial[0]
        actual = try await service.update(actual,patch:.init(name:expected.name,vulnclass:expected.vulnclass,severity:expected.severity))
        try FindingExerciseVerifier.detail(actual,expected:expected); shared.append(Self.sharedChecks[5])
        try Task.checkCancellation()
        guard gate.requestCount == 7 else { throw failure() }
        return .init(sharedChecks:shared,localChecks:local,diagnosticFieldBytes:8192,requestCount:gate.requestCount)
    }
    private func failure() -> RuntimeError { .integrity("findings boundary exercise mismatch") }
}
