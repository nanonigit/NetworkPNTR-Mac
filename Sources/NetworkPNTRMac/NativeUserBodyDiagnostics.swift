#if DEBUG
import NetworkPNTRCore
import Foundation

/// Owned data on a fresh diagnostic VM; no provider success or rendered-UI claim.
@MainActor enum NativeUserBodyDiagnostics {
    static func seed(client: any BackendJSONTransport, directory: URL) async throws -> [Int64] {
        let service = ChatService(client: client)
        guard let uploader = client as? any ChatAttachmentUploading,
              try await service.conversations().isEmpty else { throw RuntimeError.integrity("fresh user-body fixture") }
        let root = directory.appendingPathComponent("UserBodyFiles", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: root.path) else { throw RuntimeError.integrity("fresh user-body file directory") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = [root.appendingPathComponent("e\u{301}-a6.txt"), root.appendingPathComponent("empty-a6.txt")]
        let cases: [(String, String, Bool)] = [
            ("A6 full attachment body", "A6 **literal**\nFull-body sentinel 🧪", false),
            ("A6 attachment only", "", false),
            ("A6 repeated reference", "Repeated reference", true)
        ]
        var ids: [Int64] = [], rows: [[String: Any]] = []
        var ownsLocalFiles = true
        do {
            try Data("Owned native and pinned browser A6 attachment fixture\n".utf8).write(to: files[0], options: .withoutOverwriting)
            try Data().write(to: files[1], options: .withoutOverwriting)
            for (title, text, repeated) in cases {
                let conversation = try await service.create(agentKey: "auto", title: title)
                guard !ids.contains(conversation.id) else { throw RuntimeError.integrity("distinct user-body fixture owner") }
                ids.append(conversation.id)
                let uploaded = try await uploader.uploadAttachments(conversationID: conversation.id, files: repeated ? [files[0]] : files)
                guard uploaded.count == (repeated ? 1 : 2) else { throw RuntimeError.integrity("user-body fixture upload count") }
                let attachments = repeated ? [uploaded[0], uploaded[0]] : uploaded
                try await service.send(id: conversation.id, message: text, attachments: attachments)
                var history = try await service.history(id: conversation.id)
                for _ in 0..<200 {
                    if !history.running { break }
                    try await Task.sleep(for: .milliseconds(50))
                    history = try await service.history(id: conversation.id)
                }
                let users = history.items.filter { $0.kind == "user" }
                guard !history.running, users.count == 1, let user = users.first else { throw RuntimeError.integrity("persisted user-body fixture row") }
                let body = ChatUserBody(rawBody: try await service.detail(id: conversation.id, sequence: user.seq))
                guard body.text.utf8.elementsEqual(text.utf8), body.attachments == attachments,
                      user.detail?.isEmpty ?? true else { throw RuntimeError.integrity("persisted lazy user-body contract") }
                rows.append(["title": title, "text": body.text,
                             "attachments": try JSONSerialization.jsonObject(with: JSONEncoder().encode(body.attachments)),
                             "list_omits_detail": true])
            }
            try FileManager.default.removeItem(at: root); ownsLocalFiles = false
            let report: [String: Any] = ["fixture_only": true, "cases": rows]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("user-body-contract-vm.json"))
            return ids
        } catch {
            var cleanupFailed = false
            do { try await cleanup(client: client, ids: ids) } catch { cleanupFailed = true }
            if ownsLocalFiles {
                do { try FileManager.default.removeItem(at: root) } catch { cleanupFailed = true }
            }
            if cleanupFailed { throw RuntimeError.integrity("user-body fixture failed and owned cleanup did not complete") }
            throw error
        }
    }
    static func cleanup(client: any BackendJSONTransport, ids: [Int64]) async throws {
        guard ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else { throw RuntimeError.integrity("owned user-body cleanup IDs") }
        struct Deleted: Decodable { let deleted: Int64 }
        var failed = false
        for id in ids {
            // Conversation deletion cancels its run. It does not remove session files.
            do {
                let response = try await client.send(method: "DELETE", path: "/api/conversations/\(id)", body: nil, bearer: nil)
                if response.status != 404 {
                    guard response.status == 200,
                          try BackendJSONCoding.decode(Deleted.self, from: response.body).deleted == id else {
                        throw RuntimeError.integrity("owned user-body conversation cleanup")
                    }
                }
            } catch { failed = true }
            var query = URLComponents()
            query.queryItems = [URLQueryItem(name: "path", value: "sessions/conv-\(id)")]
            do {
                guard let encoded = query.percentEncodedQuery else { throw RuntimeError.integrity("owned user-body path") }
                let response = try await client.send(method: "DELETE", path: "/api/workspace/delete?" + encoded, body: nil, bearer: nil)
                guard [200, 404].contains(response.status) else { throw RuntimeError.integrity("owned user-body file cleanup") }
            } catch { failed = true }
        }
        if failed { throw RuntimeError.integrity("owned user-body cleanup incomplete") }
    }
}
#endif
