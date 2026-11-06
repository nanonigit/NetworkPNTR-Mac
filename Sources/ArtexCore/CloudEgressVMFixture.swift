#if DEBUG
import Foundation
import Synchronization

package final class CloudEgressVMFixture: Sendable {
    package struct Snapshot: Encodable, Sendable {
        package fileprivate(set) var models: [String] = []
        package fileprivate(set) var completed: [String] = []
        package fileprivate(set) var held = 0
        package fileprivate(set) var cancelled = 0
        package fileprivate(set) var denied = 0
    }

    package static let key = "synthetic-cloud-vsock-key"
    package static let prompt = "Respond to the cloud vsock fixture"
    package static let heldPrompt = "Hold this cloud vsock fixture response"

    private let state = Mutex(Snapshot())
    package var snapshot: Snapshot { state.withLock { $0 } }
    package init() {}

    package static func model(_ provider: LLMCloudProvider) -> String { "fixture-\(provider.rawValue)" }
    package static func reply(_ provider: LLMCloudProvider) -> String { "VM vsock reply from \(provider.rawValue)" }

    func exchange(
        _ request: CloudEgressRequest, _ cancellation: CloudEgressCancellation,
        _ deadline: ContinuousClock.Instant, _ receive: @escaping (CloudEgressResponseEvent) throws -> Void
    ) throws {
        let provider: LLMCloudProvider
        switch request.route {
        case .openAIModels, .openAIChat: provider = .openAI
        case .geminiModels, .geminiChat: provider = .gemini
        case .groqModels, .groqChat: provider = .groq
        default: throw reject()
        }

        let model = Self.model(provider)
        guard request.header.range(of: Data("\r\nAuthorization: Bearer \(Self.key)\r\n".utf8)) != nil else {
            throw reject()
        }
        if !request.route.requiresBody {
            let body = Data(#"{"data":[{"id":"\#(model)"}]}"#.utf8)
            try CloudEgressTransport.frameResponse(receive: receive) { consume in
                try consume(Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8))
                try consume(body)
            }
            state.withLock { $0.models.append(request.route.rawValue) }
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              json["model"] as? String == model, json["stream"] as? Bool == true,
              let messages = json["messages"] as? [[String: Any]],
              let message = messages.last, message["role"] as? String == "user" else {
            throw reject()
        }
        let content = message["content"]
        let prompt = content as? String ?? (content as? [[String: Any]])?.first?["text"] as? String
        let held = provider == .openAI && prompt == Self.heldPrompt
        guard held || prompt == Self.prompt else { throw reject() }

        try CloudEgressTransport.frameResponse(receive: receive) { consume in
            try consume(Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n".utf8))
            let finishReason = held ? "null" : #""stop""#
            let event = #"data: {"choices":[{"index":0,"delta":{"content":"\#(Self.reply(provider))"},"finish_reason":\#(finishReason)}]}"#
            try Self.chunk(event + "\n\n", consume: consume)
            if held {
                state.withLock { $0.held += 1 }
                let limit = min(deadline, ContinuousClock.now + .seconds(20))
                while !cancellation.isCancelled, ContinuousClock.now < limit {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                guard cancellation.isCancelled else { throw CloudEgressResponseError.invalidFraming }
                state.withLock { $0.cancelled += 1 }
                throw CancellationError()
            }
            try Self.chunk("data: [DONE]\n\n", consume: consume)
            try consume(Data("0\r\n\r\n".utf8))
        }
        state.withLock { $0.completed.append(request.route.rawValue) }
    }

    private func reject() -> CloudEgressError {
        state.withLock { $0.denied += 1 }
        return .invalidRequest
    }

    private static func chunk(_ value: String, consume: (Data) throws -> Void) throws {
        try consume(Data("\(String(value.utf8.count, radix: 16))\r\n".utf8))
        try consume(Data(value.utf8))
        try consume(Data("\r\n".utf8))
    }
}
#endif
