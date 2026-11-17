import XCTest
@testable import NetworkPNTRCore

@MainActor private final class LLMCancellationTransport: BackendJSONTransport {
    var calls = 0
    var cancelOnReturn = false
    var response = BackendHTTPResponse(status: 200, body: Data("{}".utf8))
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        calls += 1
        XCTAssertNil(bearer)
        if cancelOnReturn { withUnsafeCurrentTask { $0?.cancel() } }
        return response
    }
}

final class LLMTransportCancellationTests: XCTestCase {
    @MainActor private func operations(_ service: LLMService) -> [() async throws -> Void] {
        var draft = LLMProfileDraft(); draft.name = "fixture"; draft.model = "fixture"
        let snapshot = draft
        return [
            { _ = try await service.profiles() },
            { _ = try await service.save(snapshot) },
            { try await service.activate(id: "7") },
            { try await service.delete(id: "7", isActive: false) },
            { _ = try await service.pool() },
            { _ = try await service.resetPool() },
            { try await service.setRotation(enabled: true, bindFallback: nil) },
            { _ = try await service.retry() },
            { _ = try await service.saveRetry(LLMRetryPolicy()) },
            { _ = try await service.models(snapshot) },
            { _ = try await service.test(snapshot) }
        ]
    }

    @MainActor func testPreCancelledOperationsNeverReachTransport() async {
        let api = LLMCancellationTransport()
        for (index, operation) in operations(LLMService(client: api)).enumerated() {
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                do { try await operation(); XCTFail("Cancelled operation \(index) succeeded") }
                catch { XCTAssertTrue(error is CancellationError, "Operation \(index): \(type(of: error))") }
            }
            await task.value
        }
        XCTAssertEqual(api.calls, 0)
    }

    @MainActor func testCancellationAfterHandoffPrecedesStatusAndDecode() async {
        for status in [200, 503] {
            let api = LLMCancellationTransport(); api.cancelOnReturn = true
            api.response = BackendHTTPResponse(status: status, body: Data("not-json".utf8))
            for (index, operation) in operations(LLMService(client: api)).enumerated() {
                let task = Task { @MainActor in
                    do { try await operation(); XCTFail("Cancelled operation \(index) succeeded") }
                    catch { XCTAssertTrue(error is CancellationError, "Operation \(index): \(type(of: error))") }
                }
                await task.value
            }
            XCTAssertEqual(api.calls, 11)
        }
    }

    @MainActor func testOversizedDraftAndProbeNeverReachTransport() async {
        let api = LLMCancellationTransport(); let service = LLMService(client: api)
        var draft = LLMProfileDraft(); draft.name = "fixture"; draft.model = "fixture"
        draft.apiKey = String(repeating: "x", count: 4 * 1024 * 1024)
        for operation in [
            { _ = try await service.save(draft) },
            { _ = try await service.models(draft) },
            { _ = try await service.test(draft) }
        ] {
            do { try await operation(); XCTFail("Oversized JSON must fail") }
            catch { guard case BackendAPIError.invalidResponse = error else { return XCTFail("Expected bounded invalid response") } }
        }
        XCTAssertEqual(api.calls, 0)
    }

    @MainActor func testLateSuccessfulReplyIsNotReturnedAfterCancellation() async {
        let api = LLMCancellationTransport(); api.cancelOnReturn = true
        api.response = BackendHTTPResponse(status: 200, body: Data("{\"profiles\":[]}".utf8))
        let service = LLMService(client: api)
        let task = Task { @MainActor in
            do { _ = try await service.profiles(); XCTFail("Late success must not escape") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
        await task.value
        XCTAssertEqual(api.calls, 1)
    }

    @MainActor func testRequestByteLimitAllowsExactLimitAndRejectsOneExtraByte() async throws {
        let api = LLMCancellationTransport(); let service = LLMService(client: api)
        var draft = LLMProfileDraft(); draft.name = "fixture"; draft.model = "fixture"
        let overhead = try draft.encoded().count
        draft.apiKey = String(repeating: "x", count: 4 * 1024 * 1024 - overhead)
        XCTAssertEqual(try draft.encoded().count, 4 * 1024 * 1024)
        api.response = BackendHTTPResponse(status: 200, body: Data("{\"id\":7}".utf8))
        let id = try await service.save(draft)
        XCTAssertEqual(id, 7)
        draft.apiKey += "x"
        do { _ = try await service.save(draft); XCTFail("Oversized request must fail") }
        catch { guard case BackendAPIError.invalidResponse = error else { return XCTFail("Expected bounded invalid response") } }
        XCTAssertEqual(api.calls, 1)
    }

    @MainActor func testResponseByteLimitAllowsExactLimitAndRejectsOneExtraByte() async throws {
        let api = LLMCancellationTransport(); let service = LLMService(client: api)
        let prefix = Data("{\"profiles\":[]}".utf8)
        var body = prefix + Data(repeating: 0x20, count: 4 * 1024 * 1024 - prefix.count)
        api.response = BackendHTTPResponse(status: 200, body: body)
        let profiles = try await service.profiles()
        XCTAssertTrue(profiles.isEmpty)
        body.append(0x20)
        api.response = BackendHTTPResponse(status: 200, body: body)
        do { _ = try await service.profiles(); XCTFail("Oversized valid JSON must fail") }
        catch { guard case BackendAPIError.invalidResponse = error else { return XCTFail("Expected bounded invalid response") } }
        XCTAssertEqual(api.calls, 2)
    }
}
