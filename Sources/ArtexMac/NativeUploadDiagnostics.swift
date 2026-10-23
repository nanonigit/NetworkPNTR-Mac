#if DEBUG
import ArtexCore
import Foundation

/// Test-owned files and conversation on NativeDiagnostics' fresh private VM only.
@MainActor enum NativeUploadDiagnostics {
    private struct Attachment: Decodable { let name: String; let path: String; let size: Int64 }
    private struct Uploaded: Decodable { let attachments: [Attachment] }
    static func run(session: AuthenticationSession, directory: URL) async throws {
        let files = directory.appendingPathComponent("upload-selected-fixtures", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: files.path) else { throw RuntimeError.integrity("fresh selected upload fixture") }
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let second = files.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let firstBytes = Data((0..<70001).map { UInt8($0 % 256) })
        let secondBytes = Data("second synthetic attachment\n".utf8)
        let selected = [files.appendingPathComponent("fixture.bin"), files.appendingPathComponent("empty.txt"), second.appendingPathComponent("fixture.bin")]
        let expected = [firstBytes, Data(), secondBytes]
        for (url, bytes) in zip(selected, expected) {
            try bytes.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let service = ChatService(client: AuthenticatedBackendClient(session: session))
        var owned: Int64?
        do {
            let conversation = try await service.create(agentKey: "auto", title: "Native upload transport fixture")
            owned = conversation.id
            let response = try await session.authenticatedUpload(conversationID: conversation.id, files: selected)
            guard response.status == 200 else { throw RuntimeError.integrity("native upload status") }
            let uploaded = try BackendJSONCoding.decode(Uploaded.self, from: response.body)
            guard uploaded.attachments.count == 3, uploaded.attachments.map(\.name) == ["fixture.bin", "empty.txt", "fixture-1.bin"] else { throw RuntimeError.integrity("native upload ordering and duplicate names") }
            var records: [[String: Any]] = []
            for (attachment, bytes) in zip(uploaded.attachments, expected) {
                guard attachment.path == "uploads/" + attachment.name, attachment.size == Int64(bytes.count) else { throw RuntimeError.integrity("native attachment metadata") }
                var query = URLComponents()
                query.queryItems = [URLQueryItem(name: "path", value: "sessions/conv-\(conversation.id)/" + attachment.path)]
                let download = try await session.authenticatedRequest(method: "GET", path: "/api/workspace/download?" + (query.percentEncodedQuery ?? ""))
                guard download.status == 200, download.body == bytes else { throw RuntimeError.integrity("native attachment content") }
                records.append(["name": attachment.name, "path": attachment.path, "size": attachment.size, "sha256": ArtifactIntegrity.sha256(download.body)])
            }
            var query = URLComponents()
            query.queryItems = [URLQueryItem(name: "path", value: "sessions/conv-\(conversation.id)/uploads")]
            let removed = try await session.authenticatedRequest(method: "DELETE", path: "/api/workspace/delete?" + (query.percentEncodedQuery ?? ""))
            guard removed.status == 200 else { throw RuntimeError.integrity("native upload file cleanup") }
            try await service.delete(id: conversation.id); owned = nil
            try FileManager.default.removeItem(at: files)
            let result: [String: Any] = ["records": records, "actual_authenticated_vsock_upload": true, "downloaded_bytes_equal": true, "owned_files_and_conversation_cleaned": true, "large_body_limit_and_vm_stop_acceptance": "pending"]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("upload-contract-vm.json"))
        } catch {
            if let owned { try? await service.delete(id: owned) }
            try? FileManager.default.removeItem(at: files)
            throw error
        }
    }
}
#endif
