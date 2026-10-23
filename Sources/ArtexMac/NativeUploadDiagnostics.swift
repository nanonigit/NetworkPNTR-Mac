#if DEBUG
import ArtexCore
import CryptoKit
import Foundation

/// Test-owned files and conversation on NativeDiagnostics' fresh private VM only.
@MainActor enum NativeUploadDiagnostics {
    private struct Attachment: Decodable { let name: String; let path: String; let size: Int64 }
    private struct Uploaded: Decodable { let attachments: [Attachment] }
    static func run(session: AuthenticationSession, directory: URL, includeLimit: Bool = false) async throws {
        let files = directory.appendingPathComponent("upload-selected-fixtures", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: files.path) else { throw RuntimeError.integrity("fresh selected upload fixture") }
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { if FileManager.default.fileExists(atPath: files.path) { try? FileManager.default.removeItem(at: files) } }
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
            var limit: [String: Any]?
            if includeLimit { limit = try await verifyLimit(conversation.id, session: session, directory: files) }
            try await cleanup(conversation.id, session: session, service: service); owned = nil
            try FileManager.default.removeItem(at: files)
            var result: [String: Any] = ["records": records, "actual_authenticated_vsock_upload": true, "downloaded_bytes_equal": true, "owned_files_and_conversation_cleaned": true, "large_body_limit_and_vm_stop_acceptance": "pending"]
            if let limit { result["limit"] = limit }
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("upload-contract-vm.json"))
        } catch {
            if let owned {
                do { try await cleanup(owned, session: session, service: service) }
                catch { throw RuntimeError.integrity("native upload fixture cleanup failed") }
            }
            throw error
        }
    }
    private struct Entry: Decodable { let name: String; let size: Int64 }
    private struct Listing: Decodable { let entries: [Entry] }
    private static func verifyLimit(_ id: Int64, session: AuthenticationSession, directory: URL) async throws -> [String: Any] {
        let file = directory.appendingPathComponent("limit.bin")
        guard !FileManager.default.fileExists(atPath: file.path),
              FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw RuntimeError.integrity("fresh limit fixture") }
        // Every default UUID boundary has the same45-byte length. Payload plus
        // its framing, not payload alone, must equal the backend's128MiB cap.
        let overhead = try ChatMultipartPlan(files: [file]).contentLength
        let size = ChatMultipartBody.maximumBytes - overhead
        guard size > 0 else { throw RuntimeError.integrity("limit fixture overhead") }
        let writer = try FileHandle(forWritingTo: file)
        defer { try? writer.close() }
        try writer.truncate(atOffset: UInt64(size))
        guard try ChatMultipartPlan(files: [file]).contentLength == ChatMultipartBody.maximumBytes else { throw RuntimeError.integrity("exact limit framing") }
        let response = try await session.authenticatedUpload(conversationID: id, files: [file])
        guard response.status == 200 else { throw RuntimeError.integrity("exact limit upload status") }
        let uploaded = try BackendJSONCoding.decode(Uploaded.self, from: response.body)
        guard uploaded.attachments.count == 1, uploaded.attachments[0].name == "limit.bin",
              uploaded.attachments[0].path == "uploads/limit.bin", uploaded.attachments[0].size == size else { throw RuntimeError.integrity("exact limit metadata") }
        func entries() async throws -> [Entry] {
            var query = URLComponents()
            query.queryItems = [URLQueryItem(name: "path", value: "sessions/conv-\(id)/uploads")]
            let response = try await session.authenticatedRequest(method: "GET", path: "/api/workspace/list?" + (query.percentEncodedQuery ?? ""))
            guard response.status == 200 else { throw RuntimeError.integrity("limit fixture listing") }
            return try BackendJSONCoding.decode(Listing.self, from: response.body).entries
        }
        guard try await entries().first(where: { $0.name == "limit.bin" })?.size == size else { throw RuntimeError.integrity("exact limit persisted size") }
        let hashing = Task.detached { () throws -> String in
            let reader = try FileHandle(forReadingFrom: file)
            defer { try? reader.close() }
            var hash = SHA256(), count: Int64 = 0
            while let chunk = try reader.read(upToCount: 65536), !chunk.isEmpty {
                try Task.checkCancellation()
                count += Int64(chunk.count)
                guard count <= size else { throw RuntimeError.integrity("selected limit file size") }
                hash.update(data: chunk)
            }
            guard count == size else { throw RuntimeError.integrity("selected limit short file") }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
        let expectedHash = try await withTaskCancellationHandler { try await hashing.value } onCancel: { hashing.cancel() }
        try Task.checkCancellation()
        let download = try await session.authenticatedDownloadDigest(conversationID: id, name: "limit.bin", expectedSize: size)
        guard download.status == 200, download.byteCount == size, download.sha256 == expectedHash else { throw RuntimeError.integrity("large attachment full content hash") }
        try writer.truncate(atOffset: UInt64(size + 1))
        do {
            _ = try await session.authenticatedUpload(conversationID: id, files: [file])
            throw RuntimeError.integrity("over-limit upload accepted")
        } catch ChatUploadBodyError.tooLarge { }
        let after = try await entries()
        guard !after.contains(where: { $0.name == "limit-1.bin" }),
              after.first(where: { $0.name == "limit.bin" })?.size == size else { throw RuntimeError.integrity("over-limit changed stored file") }
        return ["body_bytes": ChatMultipartBody.maximumBytes, "file_size": size, "persisted_size": size,
                "over_limit_rejected": true, "duplicate_after_rejection": false,
                "downloaded_size": download.byteCount, "sha256": download.sha256, "full_content_hash_verified": true]
    }
    private static func cleanup(_ id: Int64, session: AuthenticationSession, service: ChatService) async throws {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "path", value: "sessions/conv-\(id)/uploads")]
        let removed = try await session.authenticatedRequest(method: "DELETE", path: "/api/workspace/delete?" + (query.percentEncodedQuery ?? ""))
        guard [200,404].contains(removed.status) else { throw RuntimeError.integrity("native upload file cleanup") }
        try await service.delete(id: id)
    }

}
#endif
