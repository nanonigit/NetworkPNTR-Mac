import Foundation

/// A user turn is plain text or the pinned server's persisted attachment envelope.
public struct ChatUserBody: Equatable, Sendable {
    public let text: String
    public let attachments: [ChatAttachment]
    private struct Envelope: Decodable {
        let text: String
        let attachments: [ChatAttachment]
        private enum CodingKeys: CodingKey { case text, attachments }
        init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            attachments = try fields.decode([ChatAttachment].self, forKey: .attachments)
            text = (try? fields.decode(String.self, forKey: .text)) ?? ""
        }
    }
    public init(rawBody: String) {
        // Prefix sensitivity matches startsWith("{"); do not trim user input.
        if rawBody.utf8.first == 123, let value = try? JSONDecoder().decode(Envelope.self, from: Data(rawBody.utf8)) {
            text = value.text; attachments = value.attachments
        } else {
            text = rawBody; attachments = []
        }
    }
}
