import Foundation

/// Validated guest-only paths for the draft manifest; never host URLs or downloads.
public struct TaskStagedAttachment: Decodable, Sendable, Identifiable {
    public let name: String
    public let path: String
    public let size: Int64
    public let absolutePath: String
    public var id: Data { Data(path.utf8) }
    static let draftKey = CodingUserInfoKey(rawValue: "artex.taskDraftID")!
    private enum CodingKeys: String, CodingKey { case name, path, size, abs }
    public init(from decoder: any Decoder) throws {
        guard let draftID = decoder.userInfo[Self.draftKey] as? UUID else { throw BackendAPIError.invalidResponse }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        size = try c.decode(Int64.self, forKey: .size)
        absolutePath = try c.decode(String.self, forKey: .abs)
        _ = try ChatAttachment(name: name, path: path, size: size)
        let expected = "/state/app/data/drafts/" + draftID.uuidString.lowercased() + "/uploads/" + name
        guard size <= ChatMultipartPlan.maximumBytes, absolutePath.utf8.elementsEqual(expected.utf8) else { throw BackendAPIError.invalidResponse }
    }
}

struct TaskStagingResponse: Decodable {
    let attachments: [TaskStagedAttachment]
    private enum CodingKeys: String, CodingKey { case attachments }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attachments = try c.decode([TaskStagedAttachment].self, forKey: .attachments)
        guard !attachments.isEmpty, Set(attachments.map(\.id)).count == attachments.count else { throw BackendAPIError.invalidResponse }
    }
}

@MainActor public protocol TaskStagingUploading {
    func uploadTaskStaging(draftID: UUID, files: [URL], progress: BackendUploadProgressHandler?) async throws -> [TaskStagedAttachment]
}
