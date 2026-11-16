import Foundation

/// Connects to the Mac's local runtime at a fixed loopback endpoint.
public final class OllamaCatalog: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case invalidModelName
        case unavailable
        case status(Int)
        case oversizedResponse
        case cloudEnabled
        case modelNotInstalled
        case invalidChatRequest
        case invalidChatResponse
        case unverifiedContextLength
    }

    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private let session: URLSession

    public convenience init() {
        self.init(protocolClasses: nil)
    }

    init(protocolClasses: [AnyClass]?) {
        let configuration = URLSessionConfiguration.ephemeral
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func installed() async throws -> OllamaModelList {
        try await read(path: "/api/tags")
    }

    public func running() async throws -> OllamaModelList {
        try await read(path: "/api/ps")
    }

    /// Call before sending any conversation data. Older runtimes without the
    /// status endpoint fail closed through the normal HTTP error path.
    public func requireLocalOnly() async throws {
        let status: OllamaRuntimeStatus = try await read(path: "/api/status")
        try status.requireLocalOnly()
    }

    public func metadata(forInstalledModel model: String) async throws -> OllamaModelMetadata {
        try validateModelName(model)
        let body = try JSONEncoder().encode(["model": model])
        return try await read(path: "/api/show", body: body)
    }

    public func chat(
        model: String, messages: [OllamaTextMessage], contextLength: Int = 2_048
    ) async throws -> OllamaTextReply {
        try validateModelName(model)
        let request = try OllamaTextRequest(model: model, messages: messages, contextLength: contextLength)
        let body = try JSONEncoder().encode(request)
        guard body.count <= OllamaTextRequest.bodyLimit else { throw Failure.invalidChatRequest }
        let catalog = try await installed()
        guard catalog.models.contains(where: { $0.name == model }) else { throw Failure.modelNotInstalled }
        let metadata = try await metadata(forInstalledModel: model)
        try metadata.validateContextLength(contextLength)
        try await requireLocalOnly()
        let reply: OllamaTextReply = try await read(path: "/api/chat", body: body, timeout: 120)
        guard reply.metrics.done, reply.metrics.model == model, reply.message.role == .assistant else {
            throw Failure.invalidChatResponse
        }
        return reply
    }

    private func validateModelName(_ model: String) throws {
        guard !model.isEmpty, model.utf8.count <= 1_024,
              !model.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw Failure.invalidModelName
        }
    }

    #if DEBUG
    /// Diagnostic bridge for the guest's existing OpenAI-compatible provider.
    /// The caller pins a local model and supplies no destination or credentials.
    func exchangeGuestFixture(
        model: String, body: Data,
        receive: @escaping @Sendable (CloudEgressResponseEvent) throws -> Void
    ) async throws {
        guard body.count <= OllamaTextRequest.bodyLimit,
              let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["model"] as? String == model,
              let messages = object["messages"] as? [[String: Any]],
              !messages.isEmpty, messages.count <= 128,
              messages.allSatisfy({ $0["content"] == nil || $0["content"] is NSNull || $0["content"] is String }) else {
            throw Failure.invalidChatRequest
        }
        let installed = try await installed()
        guard installed.models.contains(where: { $0.name == model }) else { throw Failure.modelNotInstalled }
        let metadata = try await metadata(forInstalledModel: model)
        try metadata.validateContextLength(OllamaGuestFixture.contextLength)
        if object["tools"] != nil, metadata.supportsTools != true { throw Failure.invalidChatRequest }
        try await requireLocalOnly()
        try Task.checkCancellation()
        let streaming = object["stream"] as? Bool == true
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/v1/chat/completions")!, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else { throw Failure.invalidChatResponse }
        try receive(.head(status: 200, type: streaming ? .eventStream : .json))
        var chunk = Data()
        var total = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            total += 1
            guard total <= 4 * 1_024 * 1_024 else { throw Failure.oversizedResponse }
            chunk.append(byte)
            if chunk.count == 1024 || byte == 10 {
                try receive(.body(chunk))
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty { try receive(.body(chunk)) }
        try Task.checkCancellation()
        let loaded = try await running()
        guard loaded.models.contains(where: {
            $0.name == model && $0.contextLength == OllamaGuestFixture.contextLength
        }) else { throw Failure.unverifiedContextLength }
        try receive(.end)
    }
    #endif

    private func read<T: Decodable>(
        path: String, body: Data? = nil, timeout: TimeInterval = 5
    ) async throws -> T {
        try Task.checkCancellation()
        guard let url = URL(string: "http://127.0.0.1:11434" + path) else { throw Failure.unavailable }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.unavailable }
        guard response.statusCode == 200 else { throw Failure.status(response.statusCode) }
        let limit = 4 * 1024 * 1024
        guard response.expectedContentLength <= limit else { throw Failure.oversizedResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw Failure.oversizedResponse }
            data.append(byte)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
