import Foundation

/// Metadata of one uploaded session file. Guest abs and Mac paths are not retained.
public struct ChatAttachment: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let path: String
    public let size: Int64
    /// Linux guest paths are byte identities, not canonically equivalent Swift strings.
    public var id: Data { Data(path.utf8) }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.size == rhs.size && lhs.name.utf8.elementsEqual(rhs.name.utf8) && lhs.path.utf8.elementsEqual(rhs.path.utf8)
    }
    private enum CodingKeys: String, CodingKey { case name, path, size }
    public init(name: String, path: String, size: Int64) throws {
        _ = try ChatAttachmentDownload(conversationID: 1, name: name, expectedSize: size)
        guard path.utf8.elementsEqual(("uploads/" + name).utf8) else { throw BackendAPIError.invalidResponse }
        self.name = name; self.path = path; self.size = size
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: values.decode(String.self, forKey: .name),
                      path: values.decode(String.self, forKey: .path), size: values.decode(Int64.self, forKey: .size))
    }
    var json: [String: Any] { ["name":name, "path":path, "size":size] }
}

public struct ChatUploadResponse: Decodable, Sendable {
    public let attachments: [ChatAttachment]
    private enum CodingKeys: String, CodingKey { case attachments }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        attachments = try values.decode([ChatAttachment].self, forKey: .attachments)
        guard !attachments.isEmpty, Set(attachments.map(\.id)).count == attachments.count else { throw BackendAPIError.invalidResponse }
    }
}

@MainActor public protocol ChatAttachmentUploading {
    func uploadAttachments(conversationID: Int64, files: [URL], progress: BackendUploadProgressHandler?) async throws -> [ChatAttachment]
}
public extension ChatAttachmentUploading {
    func uploadAttachments(conversationID: Int64, files: [URL]) async throws -> [ChatAttachment] {
        try await uploadAttachments(conversationID: conversationID, files: files, progress: nil)
    }
}

public struct ChatAttachmentUploadState: Sendable {
    public let operationID: UUID
    public let conversationID: Int64?
    public let progress: BackendUploadProgress?
}
