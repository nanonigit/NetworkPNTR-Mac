#if DEBUG
import Foundation
import Synchronization

package final class CloudEgressVMFixture: Sendable {
    package struct Snapshot: Encodable, Sendable {
        package fileprivate(set) var models: [String] = []
        package fileprivate(set) var completed: [String] = []
        package fileprivate(set) var openAIOutputLanguages: [String] = []
        package fileprivate(set) var scheduledReplies = 0
        package fileprivate(set) var held = 0
        package fileprivate(set) var cancelled = 0
        package fileprivate(set) var denied = 0
        package fileprivate(set) var lastDenial: String?
    }

    package static let key = "synthetic-cloud-vsock-key"
    package static let prompt = "Respond to the cloud vsock fixture"
    package static let scheduledPrompt = "Synthetic interval trigger fixture"
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
        case .anthropicModels, .anthropicMessages: provider = .anthropic
        case .geminiModels, .geminiChat: provider = .gemini
        case .groqModels, .groqChat: provider = .groq
        default: throw reject("route")
        }

        let model = Self.model(provider)
        let header = String(decoding: request.header, as: UTF8.self)
        let authorization = provider == .anthropic
            ? ["x-api-key: \(Self.key)", "anthropic-version: 2023-06-01"]
            : ["Authorization: Bearer \(Self.key)"]
        guard authorization.allSatisfy({ header.contains("\r\n\($0)\r\n") }) else { throw reject("authorization") }
        if !request.route.requiresBody {
            let json = provider == .anthropic
                ? #"{"data":[{"id":"\#(model)","type":"model","display_name":"Fixture","created_at":"2026-01-01T00:00:00Z"}],"has_more":false,"first_id":"\#(model)","last_id":"\#(model)"}"#
                : #"{"data":[{"id":"\#(model)"}]}"#
            let body = Data(json.utf8)
            try CloudEgressTransport.frameResponse(receive: receive) { consume in
                try consume(Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8))
                try consume(body)
            }
            state.withLock { $0.models.append(request.route.rawValue) }
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              json["model"] as? String == model, json["stream"] as? Bool == true,
              let messages = json["messages"] as? [[String: Any]] else {
            throw reject("body")
        }
        guard let message = messages.last, message["role"] as? String == "user" else {
            throw reject("role")
        }
        let content = message["content"]
        let blocks = content as? [[String: Any]] ?? []
        let texts = (content as? String).map { [$0] }
            ?? blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
        let held = provider == .openAI && texts.contains(Self.heldPrompt)
        let scheduled = provider == .openAI && texts.contains {
            $0.hasPrefix(Self.scheduledPrompt + "\n\n【本次为定时触发】")
        }
        guard held || scheduled || texts.contains(Self.prompt) else { throw reject("prompt") }

        if provider == .openAI, !held, !scheduled {
            let system = messages.filter { $0["role"] as? String == "system" }
                .compactMap { $0["content"] as? String }
                .joined(separator: "\n")
            let english = system.contains("自然语言文字一律用【英语（English）】")
            let japanese = system.contains("自然语言文字一律用【日语（日本語）】")
            let language = english == japanese ? "unconfirmed" : (english ? "en" : "ja")
            state.withLock { $0.openAIOutputLanguages.append(language) }
        }

        try CloudEgressTransport.frameResponse(receive: receive) { consume in
            try consume(Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n".utf8))
            if provider == .anthropic {
                try Self.anthropicStream(model: model, consume: consume)
                try consume(Data("0\r\n\r\n".utf8))
                return
            }
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
        state.withLock {
            $0.completed.append(request.route.rawValue)
            if scheduled { $0.scheduledReplies += 1 }
        }
    }

    private func reject(_ reason: String) -> CloudEgressError {
        state.withLock {
            $0.denied += 1
            $0.lastDenial = reason
        }
        return .invalidRequest
    }

    private static func anthropicStream(model: String, consume: (Data) throws -> Void) throws {
        let events: [(String, String)] = [
            ("message_start", #","message":{"id":"msg_fixture","type":"message","role":"assistant","model":"\#(model)","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":3,"output_tokens":0}}"#),
            ("content_block_start", #","index":0,"content_block":{"type":"text","text":""}"#),
            ("content_block_delta", #","index":0,"delta":{"type":"text_delta","text":"\#(reply(.anthropic))"}"#),
            ("content_block_stop", #","index":0"#),
            ("message_delta", #","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":4}"#),
            ("message_stop", "")
        ]
        for (type, fields) in events {
            try chunk("event: \(type)\ndata: {\"type\":\"\(type)\"\(fields)}\n\n", consume: consume)
        }
    }

    private static func chunk(_ value: String, consume: (Data) throws -> Void) throws {
        try consume(Data("\(String(value.utf8.count, radix: 16))\r\n".utf8))
        try consume(Data(value.utf8))
        try consume(Data("\r\n".utf8))
    }
}
#endif
