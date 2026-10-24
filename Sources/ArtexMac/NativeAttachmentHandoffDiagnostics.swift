#if DEBUG
import ArtexCore
import Foundation

@MainActor private final class HandoffRecordingClient: BackendJSONTransport, ChatAttachmentUploading {
    private let base: AuthenticatedBackendClient
    var createdIDs: [Int64] = []
    var sendStatuses: [Int] = []
    var relativeMetadataOnly = true
    init(session: AuthenticationSession) { base = AuthenticatedBackendClient(session:session) }
    func uploadAttachments(conversationID: Int64, files: [URL], progress: BackendUploadProgressHandler?) async throws -> [ChatAttachment] {
        try await base.uploadAttachments(conversationID:conversationID,files:files,progress:progress)
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        let response = try await base.send(method:method,path:path,body:body,bearer:bearer)
        if method == "POST", path == "/api/conversations", response.status == 200 {
            createdIDs.append(try BackendJSONCoding.decode(ChatConversation.self,from:response.body).id)
        }
        if method == "POST", path.hasPrefix("/api/conversations/"), path.hasSuffix("/messages") {
            sendStatuses.append(response.status)
            guard let body, let object = try JSONSerialization.jsonObject(with:body) as? [String:Any],
                  let attachments = object["attachments"] as? [[String:Any]] else { throw BackendAPIError.invalidResponse }
            relativeMetadataOnly = relativeMetadataOnly && !attachments.isEmpty && attachments.allSatisfy { Set($0.keys) == ["name","path","size"] }
        }
        return response
    }
}

/// This fixture must run on NativeDiagnostics' fresh account before LLM setup.
@MainActor enum NativeAttachmentHandoffDiagnostics {
    static func run(session: AuthenticationSession, directory: URL) async throws {
        let client = HandoffRecordingClient(session:session), service = ChatService(client:client)
        guard try await service.conversations().isEmpty, try await LLMService(client:client).profiles().isEmpty else { throw RuntimeError.integrity("fresh no-LLM attachment fixture") }
        let selected = directory.appendingPathComponent("attachment-handoff-selected",isDirectory:true)
        guard !FileManager.default.fileExists(atPath:selected.path) else { throw RuntimeError.integrity("fresh handoff selections") }
        try FileManager.default.createDirectory(at:selected,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:selected) }
        // Darwin file URLs decompose path components; use an explicit stable form.
        let names = ["e\u{301}.txt","other.bin","empty.txt"], bytes = [Data([1]),Data([2]),Data()]
        var files: [URL] = []
        for index in names.indices {
            let folder = selected.appendingPathComponent(String(index),isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let file = folder.appendingPathComponent(names[index])
            try bytes[index].write(to:file)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
            files.append(file)
        }
        do {
            let workspace = ChatWorkspace(client:client)
            workspace.agentKey = "auto"; workspace.transcript.draft = "Native attachment handoff fixture"
            guard await workspace.pickFiles(files) else { throw RuntimeError.integrity("native attachment upload: " + (workspace.uploadError ?? "missing acceptance")) }
            guard let owner = workspace.transcript.selectedID else { throw RuntimeError.integrity("native attachment owner selection") }
            guard workspace.transcript.hasLoadedHistory else { throw RuntimeError.integrity("native attachment history readiness") }
            guard !workspace.isUploading else { throw RuntimeError.integrity("native attachment terminal upload") }
            guard workspace.transcript.draft == "Native attachment handoff fixture", workspace.transcript.draft(for:nil).isEmpty else { throw RuntimeError.integrity("native attachment text handoff") }
            let attachments = workspace.transcript.attachments
            guard attachments.count == 3, Set(attachments.map(\.id)).count == 3 else { throw RuntimeError.integrity("native distinct attachment metadata") }
            var records: [[String:Any]] = []
            for index in names.indices {
                let attachment = attachments[index]
                guard attachment.name.utf8.elementsEqual(names[index].utf8), attachment.size == Int64(bytes[index].count) else { throw RuntimeError.integrity("native Unicode attachment bytes") }
                let response = try await client.send(method:"GET",path:route(owner,operation:"download",suffix:"/"+attachment.name),body:nil,bearer:nil)
                guard response.status == 200, response.body == bytes[index] else { throw RuntimeError.integrity("native handoff attachment content") }
                records.append(["name":attachment.name,"path":attachment.path,"size":attachment.size,"sha256":ArtifactIntegrity.sha256(response.body)])
            }
            workspace.transcript.draft = ""
            guard !(await workspace.send()), client.sendStatuses == [503], workspace.transcript.attachments == attachments,
                  workspace.transcript.draft.isEmpty else { throw RuntimeError.integrity("native attachment-only send recovery") }
            workspace.transcript.draft = "retry text"
            guard !(await workspace.send()), client.sendStatuses == [503,503], client.relativeMetadataOnly,
                  workspace.transcript.draft == "retry text", workspace.transcript.attachments == attachments else { throw RuntimeError.integrity("native mixed attachment send recovery") }
            workspace.transcript.removeAttachment(path:attachments[0].path,for:owner)
            guard workspace.transcript.attachments == Array(attachments.dropFirst()) else { throw RuntimeError.integrity("native exact draft card removal") }
            let listing = try await client.send(method:"GET",path:route(owner,operation:"list"),body:nil,bearer:nil)
            struct Entry: Decodable { let name: String }
            struct Listing: Decodable { let entries: [Entry] }
            guard listing.status == 200 else { throw RuntimeError.integrity("native handoff guest listing") }
            let persisted = try BackendJSONCoding.decode(Listing.self,from:listing.body).entries.map(\.name)
            guard Set(persisted.map { Data($0.utf8) }) == Set(names.map { Data($0.utf8) }) else { throw RuntimeError.integrity("card removal deleted guest data") }
            let other = try await service.create(agentKey:"auto",title:"Native other attachment fixture")
            await workspace.select(other.id); workspace.transcript.draft = "other"
            guard workspace.transcript.attachments.isEmpty else { throw RuntimeError.integrity("attachment selection isolation") }
            await workspace.select(owner)
            guard workspace.transcript.draft == "retry text", workspace.transcript.attachments.count == 2,
                  try await service.history(id:owner).items.isEmpty else { throw RuntimeError.integrity("native attachment draft retention") }
            try await cleanup(client:client,service:service)
            try FileManager.default.removeItem(at:selected)
            let result: [String:Any] = ["records":records,"failed_send_statuses":client.sendStatuses,
                "guest_names_after_remove":persisted.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) },
                "history_empty_after_rejections":true,"owned_files_and_conversation_cleaned":true,
                "native_create_text_handoff":true,"native_failed_send_restoration":true,"native_selection_isolation":true,
                "metadata_keys":["name","path","size"],"ui_picker_cards_parity":"pending"]
            try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("attachment-handoff-vm.json"))
        } catch {
            do { try await cleanup(client:client,service:service) }
            catch { throw RuntimeError.integrity("native handoff fixture cleanup failed") }
            throw error
        }
    }
    private static func route(_ id: Int64, operation: String, suffix: String = "") -> String {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name:"path",value:"sessions/conv-\(id)/uploads"+suffix)]
        return "/api/workspace/"+operation+"?"+(query.percentEncodedQuery ?? "")
    }
    private static func cleanup(client: HandoffRecordingClient, service: ChatService) async throws {
        for id in client.createdIDs.reversed() {
            let response = try await client.send(method:"DELETE",path:route(id,operation:"delete"),body:nil,bearer:nil)
            guard [200,404].contains(response.status) else { throw RuntimeError.integrity("handoff file cleanup") }
            try await service.delete(id:id)
        }
        client.createdIDs = []
    }
}
#endif
