import Foundation
import Observation

public enum AuthenticationPhase: String, Sendable { case checking, needsSetup, needsLogin, authenticated, unavailable }

@MainActor @Observable public final class AuthenticationSession {
    public private(set) var phase: AuthenticationPhase = .checking
    public var error: String? { failure?.text(language: .japanese) }
    public private(set) var failure: AppErrorMessage?
    public private(set) var isBusy = false
    @ObservationIgnored private let client: any BackendJSONTransport
    @ObservationIgnored private let vault: any SessionVault
    @ObservationIgnored private let setupToken: String
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var uploadProgress: [UUID: BackendUploadProgressGate] = [:]
    private struct Status: Decodable { let initialized: Bool; let setup_token_required: Bool }
    private struct Session: Decodable { let token: String }
    public init(client: any BackendJSONTransport, vault: any SessionVault, setupToken: String) {
        self.client = client; self.vault = vault; self.setupToken = setupToken
    }
    #if DEBUG
    /// Diagnostic witness of one authentication epoch; exposes no credentials.
    package func exportOwnershipWitness() throws -> @MainActor () throws -> Void {
        guard phase == .authenticated, token != nil else { throw CancellationError() }
        let ticket = revision
        return { [weak self] in
            guard let self, self.revision == ticket, self.phase == .authenticated else { throw CancellationError() }
        }
    }
    #endif
    public func refresh() async {
        guard !isBusy else { return }
        isBusy = true; failure = nil; token = nil; advanceRevision(); phase = .checking
        defer { isBusy = false }
        do {
            let status: Status = try await request(method: "GET", path: "/api/auth/status")
            guard status.initialized != status.setup_token_required else { throw BackendAPIError.invalidResponse }
            if !status.initialized {
                try vault.remove()
                phase = .needsSetup
            } else if let saved = try vault.load() {
                let response = try await client.send(method: "GET", path: "/api/llm/profiles", body: nil, bearer: saved)
                if response.status == 200 { token = saved; phase = .authenticated }
                else if response.status == 401 { try vault.remove(); phase = .needsLogin }
                else { throw BackendAPIError.status(response.status) }
            } else { phase = .needsLogin }
        } catch { phase = .unavailable; self.failure = AppErrorMessage(error) }
    }
    public func setup(password: String, confirmation: String) async {
        guard !isBusy, phase == .needsSetup else { return }
        do {
            guard password == confirmation else { throw BackendAPIError.validation(.passwordMismatch) }
            guard password.unicodeScalars.count >= 8 else { throw BackendAPIError.validation(.passwordShort) }
            guard password.utf8.count <= 72 else { throw BackendAPIError.validation(.passwordBytes) }
            isBusy = true; failure = nil
            defer { isBusy = false }
            let body = try JSONSerialization.data(withJSONObject: ["password": password, "setup_token": setupToken])
            let session: Session = try await request(method: "POST", path: "/api/auth/init", body: body)
            // The server has created the account even if secure storage subsequently fails.
            phase = .needsLogin
            try accept(session.token)
        } catch { self.failure = AppErrorMessage(error) }
    }
    public func login(password: String, agreed: Bool) async {
        guard !isBusy, phase == .needsLogin else { return }
        do {
            guard agreed else { throw BackendAPIError.validation(.termsRequired) }
            guard !password.isEmpty else { throw BackendAPIError.validation(.passwordRequired) }
            isBusy = true; failure = nil
            defer { isBusy = false }
            let body = try JSONSerialization.data(withJSONObject: ["username": "ARTEX", "password": password])
            let session: Session = try await request(method: "POST", path: "/api/auth/login", body: body)
            try accept(session.token)
        } catch { self.failure = AppErrorMessage(error) }
    }
    public func logout() {
        guard !isBusy else { return }
        do { try vault.remove(); token = nil; advanceRevision(); phase = .needsLogin; failure = nil }
        catch { self.failure = AppErrorMessage(error) }
    }
    public func authenticatedRequest(method: String, path: String, body: Data? = nil) async throws -> BackendHTTPResponse {
        guard phase == .authenticated, let token else { throw BackendAPIError.status(401) }
        let ticket = revision
        let response = try await client.send(method: method, path: path, body: body, bearer: token)
        try validateReply(response, ticket: ticket)
        return response
    }
    public func authenticatedUpload(conversationID: Int64, files: [URL], progress: BackendUploadProgressHandler? = nil) async throws -> BackendHTTPResponse {
        try Task.checkCancellation()
        guard phase == .authenticated, token != nil else { throw BackendAPIError.status(401) }
        guard conversationID > 0, !files.isEmpty else { throw ChatUploadBodyError.invalidFile }
        guard let uploader = client as? any BackendMultipartTransport else { throw BackendAPIError.invalidResponse }
        return try await authenticatedUploadOperation(progress: progress) { token, forwarded in
            try await uploader.upload(conversationID: conversationID, files: files, bearer: token, progress: forwarded)
        }
    }
    public func authenticatedStagingUpload(draftID: UUID, files: [URL], progress: BackendUploadProgressHandler? = nil) async throws -> BackendHTTPResponse {
        try Task.checkCancellation()
        guard phase == .authenticated, token != nil else { throw BackendAPIError.status(401) }
        guard !files.isEmpty else { throw ChatUploadBodyError.invalidFile }
        guard let uploader = client as? any BackendStagingMultipartTransport else { throw BackendAPIError.invalidResponse }
        return try await authenticatedUploadOperation(progress: progress) { token, forwarded in
            try await uploader.uploadStaging(draftID: draftID, files: files, bearer: token, progress: forwarded)
        }
    }
    private func authenticatedUploadOperation(progress: BackendUploadProgressHandler?, operation: (String, BackendUploadProgressHandler?) async throws -> BackendHTTPResponse) async throws -> BackendHTTPResponse {
        guard phase == .authenticated, let token else { throw BackendAPIError.status(401) }
        let ticket = revision
        let identifier = UUID()
        let gate = progress.map { BackendUploadProgressGate($0) }
        if let gate { uploadProgress[identifier] = gate }
        defer { uploadProgress.removeValue(forKey: identifier)?.close(); gate?.close() }
        let forwarded: BackendUploadProgressHandler?
        if let gate { forwarded = { @Sendable value in gate.receive(value) } }
        else { forwarded = nil }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let response = try await operation(token, forwarded)
            try Task.checkCancellation()
            try validateReply(response, ticket: ticket)
            return response
        } onCancel: { gate?.close() }
    }
    public func authenticatedDownloadDigest(conversationID: Int64, name: String, expectedSize: Int64) async throws -> BackendDownloadResult {
        try Task.checkCancellation()
        guard phase == .authenticated, let token else { throw BackendAPIError.status(401) }
        let attachment = try ChatAttachmentDownload(conversationID: conversationID, name: name, expectedSize: expectedSize)
        guard let downloader = client as? any BackendAttachmentDownloadTransport else { throw BackendAPIError.invalidResponse }
        let ticket = revision
        let response = try await downloader.downloadDigest(attachment, bearer: token)
        try Task.checkCancellation()
        try validateReply(BackendHTTPResponse(status: response.status, body: Data()), ticket: ticket)
        return response
    }
    public func authenticatedEvidenceExport(_ manifest: FindingEvidenceDownload, destination: EvidenceExportDestination) async throws -> EvidenceExportReceipt {
        try await authenticatedBodyExport(manifest) { token in
            guard let downloader = self.client as? any BackendEvidenceDownloadTransport else { throw BackendAPIError.invalidResponse }
            return try await downloader.stageEvidence(manifest, destination: destination, bearer: token)
        }
    }
    public func authenticatedTrafficBlobExport(_ manifest: TrafficBlobDownload, destination: EvidenceExportDestination) async throws -> EvidenceExportReceipt {
        try await authenticatedBodyExport(manifest) { token in
            guard let downloader = self.client as? any BackendTrafficBlobDownloadTransport else { throw BackendAPIError.invalidResponse }
            return try await downloader.stageTrafficBlob(manifest, destination: destination, bearer: token)
        }
    }
    private func authenticatedBodyExport(_ manifest: any EvidenceBodyManifest,
                                       stage: @MainActor (String) async throws -> EvidenceExportReceipt) async throws -> EvidenceExportReceipt {
        try Task.checkCancellation()
        guard phase == .authenticated, let token else { throw BackendAPIError.status(401) }
        let ticket = revision
        let receipt = try await stage(token)
        do {
            try Task.checkCancellation()
            try receipt.validateOwnership()
            try validateReply(BackendHTTPResponse(status: receipt.result.status, body: Data()), ticket: ticket)
            guard receipt.result.status == 200 else { throw BackendAPIError.status(receipt.result.status) }
            try receipt.requireSuccess(manifest)
            receipt.restrict { [weak self] in
                guard let self, self.revision == ticket, self.phase == .authenticated else { throw CancellationError() }
            }
            return receipt
        } catch {
            try receipt.discard()
            throw error
        }
    }
    private func validateReply(_ response: BackendHTTPResponse, ticket: UUID) throws {
        guard revision == ticket, phase == .authenticated else { throw CancellationError() }
        if response.status == 401 {
            token = nil; advanceRevision(); phase = .needsLogin
            // In-memory authentication must expire even if Keychain removal fails.
            try vault.remove()
        }
    }
    private func advanceRevision() {
        for gate in uploadProgress.values { gate.close() }
        uploadProgress.removeAll()
        revision = UUID()
    }
    private func accept(_ value: String) throws {
        _ = try BackendHTTPRequest.make(method: "GET", path: "/api/auth/status", body: nil, bearer: value)
        try vault.save(value)
        token = value; advanceRevision(); phase = .authenticated; failure = nil
    }
    private func request<T: Decodable>(method: String, path: String, body: Data? = nil) async throws -> T {
        let response = try await client.send(method: method, path: path, body: body, bearer: nil)
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw BackendAPIError.invalidResponse }
    }
}
