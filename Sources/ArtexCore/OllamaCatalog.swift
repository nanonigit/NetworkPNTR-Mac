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
