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
    private let runtime: OllamaCatalog
    package struct Snapshot: Sendable {
        package var completed = 0
        package var active = 0
        package var generated = 0
        package var canceled = 0
        package var streamFinished = 0
        package var canceledWhileStreaming = 0
    }
    private let state = Mutex(Snapshot())
    package var snapshot: Snapshot { state.withLock { $0 } }
    package var requestCount: Int { state.withLock { $0.completed } }

    package convenience init(model: String) { self.init(model: model, runtime: OllamaCatalog()) }
    init(model: String, runtime: OllamaCatalog) { self.model = model; self.runtime = runtime }

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
        let witness = Mutex(OllamaStreamWitness())
        state.withLock { $0.active += 1 }
        let task = Task.detached { [self] in
            defer {
                state.withLock { $0.active -= 1 }
                completed.signal()
            }
            do {
                try await runtime.exchangeGuestFixture(model: model, body: request.body, streamFinished: {
                    if witness.withLock({ $0.finish() }) {
                        self.state.withLock { $0.streamFinished += 1 }
                    }
                }) { event in
                    if case .body(let bytes) = event {
                        let observation = try witness.withLock { witness in
                            let wasEnded = witness.ended
                            let generated = try witness.consume(bytes)
                            return (generated: generated, finished: !wasEnded && witness.ended && witness.observed)
                        }
                        self.state.withLock {
                            if observation.generated { $0.generated += 1 }
                            if observation.finished { $0.streamFinished += 1 }
                        }
                    }
                    try sink.receive(event)
                }
                state.withLock { $0.completed += 1 }
                succeeded.withLock { $0 = true }
            } catch {
                let wasStreaming = witness.withLock { $0.finish() }
                state.withLock {
                    if wasStreaming { $0.streamFinished += 1 }
                    if Task.isCancelled || cancellation.isCancelled {
                        $0.canceled += 1
                        if wasStreaming, cancellation.isCancelled, ContinuousClock.now < deadline {
                            $0.canceledWhileStreaming += 1
                        }
                    }
                }
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

/// Retains only an incomplete SSE line, never the generated conversation.
struct OllamaStreamWitness {
    private var line = Data()
    private(set) var observed = false
    private(set) var ended = false

    mutating func finish() -> Bool {
        let wasStreaming = observed && !ended
        ended = true
        line.removeAll()
        return wasStreaming
    }

    mutating func consume(_ bytes: Data) throws -> Bool {
        guard !ended else { return false }
        let wasObserved = observed
        for byte in bytes {
            if byte != 10 {
                guard line.count < 65_536 else { throw OllamaCatalog.Failure.oversizedResponse }
                line.append(byte)
                continue
            }
            let text = String(decoding: line, as: UTF8.self)
            line.removeAll(keepingCapacity: true)
            if text.trimmingCharacters(in: .whitespacesAndNewlines) == "data: [DONE]" {
                _ = finish()
                break
            }
            guard text.hasPrefix("data:"),
                  let data = text.dropFirst(5).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = object["choices"] as? [[String: Any]] else { continue }
            let generated = choices.contains { choice in
                guard let delta = choice["delta"] as? [String: Any] else { return false }
                return ["content", "reasoning_content", "reasoning"].contains {
                    (delta[$0] as? String)?.isEmpty == false
                }
            }
            if generated {
                observed = true
            }
            if choices.contains(where: { $0["finish_reason"] is String }) {
                _ = finish()
                break
            }
        }
        return !wasObserved && observed
    }
}
#endif
