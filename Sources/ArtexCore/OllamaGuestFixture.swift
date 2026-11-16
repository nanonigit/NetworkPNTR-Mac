#if DEBUG
import Foundation
import Synchronization

/// Connects a disposable guest provider to a selected local model for validation.
/// This diagnostic uses the existing cloud wire format without changing its
/// production routes or accepting a cloud credential.
package final class OllamaGuestFixture: Sendable {
    package static let key = "artex-local-inference-fixture"
    package static let contextLength = 8_192
    private let model: String
    private let runtime = OllamaCatalog()
    private let calls = Mutex(0)
    package var requestCount: Int { calls.withLock { $0 } }

    package init(model: String) { self.model = model }

    // The writer is invoked only by this exchange's async worker. The outer
    // worker drains that task before releasing the socket and its writer.
    private final class Sink: @unchecked Sendable {
        let receive: (CloudEgressResponseEvent) throws -> Void
        init(_ receive: @escaping (CloudEgressResponseEvent) throws -> Void) { self.receive = receive }
    }

    func exchange(
        _ request: CloudEgressRequest, cancellation: CloudEgressCancellation,
        deadline: ContinuousClock.Instant,
        receive: @escaping (CloudEgressResponseEvent) throws -> Void
    ) throws {
        let streaming = request.header.range(of: Data("Accept: text/event-stream\r\n".utf8)) != nil
        let expected = try CloudEgressRequest(route: .openAIChat, apiKey: Self.key, body: request.body, streaming: streaming)
        guard request.route == .openAIChat, request.header == expected.header,
              !cancellation.isCancelled, ContinuousClock.now < deadline else {
            throw CloudEgressError.invalidRequest
        }
        let sink = Sink(receive)
        let completed = DispatchSemaphore(value: 0)
        let succeeded = Mutex(false)
        let task = Task.detached { [self] in
            defer { completed.signal() }
            do {
                try await runtime.exchangeGuestFixture(model: model, body: request.body) { event in
                    try sink.receive(event)
                }
                calls.withLock { $0 += 1 }
                succeeded.withLock { $0 = true }
            } catch {
                // Guest sees a failed exchange without local diagnostics or prompts.
            }
        }
        defer { task.cancel() }
        while completed.wait(timeout: .now() + .milliseconds(25)) == .timedOut {
            if cancellation.isCancelled || ContinuousClock.now >= deadline { task.cancel() }
        }
        guard !cancellation.isCancelled, ContinuousClock.now < deadline,
              succeeded.withLock({ $0 }) else { throw CloudEgressTransportError.transferFailed }
    }
}
#endif
