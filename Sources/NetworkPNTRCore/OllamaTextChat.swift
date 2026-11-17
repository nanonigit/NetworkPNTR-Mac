import Foundation

public struct OllamaTextMessage: Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct OllamaTextReply: Decodable, Sendable {
    public let message: OllamaTextMessage
    public let metrics: OllamaInferenceMetrics

    private enum CodingKeys: String, CodingKey { case message }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(OllamaTextMessage.self, forKey: .message)
        metrics = try OllamaInferenceMetrics(from: decoder)
    }
}

struct OllamaTextRequest: Encodable {
    static let bodyLimit = 256 * 1_024

    struct Options: Encodable {
        let num_ctx: Int
        let num_predict = 1_024
    }

    let model: String
    let messages: [OllamaTextMessage]
    let stream = false
    let options: Options

    init(model: String, messages: [OllamaTextMessage], contextLength: Int) throws {
        guard (1...128).contains(messages.count), messages.last?.role == .user,
              (1...32_768).contains(contextLength) else { throw OllamaCatalog.Failure.invalidChatRequest }
        var remainingBytes = Self.bodyLimit
        for message in messages {
            let size = message.content.utf8.count
            guard size <= remainingBytes else { throw OllamaCatalog.Failure.invalidChatRequest }
            remainingBytes -= size
        }
        self.model = model
        self.messages = messages
        options = Options(num_ctx: contextLength)
    }
}
