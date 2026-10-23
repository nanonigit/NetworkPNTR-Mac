import Foundation
import Observation

public enum AuthenticationPhase: String, Sendable { case checking, needsSetup, needsLogin, authenticated, unavailable }

@MainActor @Observable public final class AuthenticationSession {
    public private(set) var phase: AuthenticationPhase = .checking
    public private(set) var error: String?
    public private(set) var isBusy = false
    @ObservationIgnored private let client: any BackendJSONTransport
    @ObservationIgnored private let vault: any SessionVault
    @ObservationIgnored private let setupToken: String
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var revision = UUID()
    private struct Status: Decodable { let initialized: Bool; let setup_token_required: Bool }
    private struct Session: Decodable { let token: String }
    public init(client: any BackendJSONTransport, vault: any SessionVault, setupToken: String) {
        self.client = client; self.vault = vault; self.setupToken = setupToken
    }
    public func refresh() async {
        guard !isBusy else { return }
        isBusy = true; error = nil; token = nil; revision = UUID(); phase = .checking
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
        } catch { phase = .unavailable; self.error = error.localizedDescription }
    }
    public func setup(password: String, confirmation: String) async {
        guard !isBusy, phase == .needsSetup else { return }
        do {
            guard password == confirmation else { throw BackendAPIError.validation("パスワードが一致しません。") }
            guard password.unicodeScalars.count >= 8 else { throw BackendAPIError.validation("パスワードは8文字以上で入力してください。") }
            guard password.utf8.count <= 72 else { throw BackendAPIError.validation("パスワードはUTF-8で72バイト以内にしてください。") }
            isBusy = true; error = nil
            defer { isBusy = false }
            let body = try JSONSerialization.data(withJSONObject: ["password": password, "setup_token": setupToken])
            let session: Session = try await request(method: "POST", path: "/api/auth/init", body: body)
            // The server has created the account even if secure storage subsequently fails.
            phase = .needsLogin
            try accept(session.token)
        } catch { self.error = error.localizedDescription }
    }
    public func login(password: String, agreed: Bool) async {
        guard !isBusy, phase == .needsLogin else { return }
        do {
            guard agreed else { throw BackendAPIError.validation("利用条件を確認して同意してください。") }
            guard !password.isEmpty else { throw BackendAPIError.validation("パスワードを入力してください。") }
            isBusy = true; error = nil
            defer { isBusy = false }
            let body = try JSONSerialization.data(withJSONObject: ["username": "ARTEX", "password": password])
            let session: Session = try await request(method: "POST", path: "/api/auth/login", body: body)
            try accept(session.token)
        } catch { self.error = error.localizedDescription }
    }
    public func logout() {
        guard !isBusy else { return }
        do { try vault.remove(); token = nil; revision = UUID(); phase = .needsLogin; error = nil }
        catch { self.error = error.localizedDescription }
    }
    public func authenticatedRequest(method: String, path: String, body: Data? = nil) async throws -> BackendHTTPResponse {
        guard phase == .authenticated, let token else { throw BackendAPIError.status(401) }
        let ticket = revision
        let response = try await client.send(method: method, path: path, body: body, bearer: token)
        try validateReply(response, ticket: ticket)
        return response
    }
    public func authenticatedUpload(conversationID: Int64, files: [URL]) async throws -> BackendHTTPResponse {
        guard phase == .authenticated, let token else { throw BackendAPIError.status(401) }
        guard conversationID > 0, !files.isEmpty else { throw ChatUploadBodyError.invalidFile }
        guard let uploader = client as? any BackendMultipartTransport else { throw BackendAPIError.invalidResponse }
        let ticket = revision
        let response = try await uploader.upload(conversationID: conversationID, files: files, bearer: token)
        try validateReply(response, ticket: ticket)
        return response
    }
    private func validateReply(_ response: BackendHTTPResponse, ticket: UUID) throws {
        guard revision == ticket, phase == .authenticated else { throw CancellationError() }
        if response.status == 401 {
            token = nil; revision = UUID(); phase = .needsLogin
            // In-memory authentication must expire even if Keychain removal fails.
            try vault.remove()
        }
    }
    private func accept(_ value: String) throws {
        _ = try BackendHTTPRequest.make(method: "GET", path: "/api/auth/status", body: nil, bearer: value)
        try vault.save(value)
        token = value; revision = UUID(); phase = .authenticated; error = nil
    }
    private func request<T: Decodable>(method: String, path: String, body: Data? = nil) async throws -> T {
        let response = try await client.send(method: method, path: path, body: body, bearer: nil)
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw BackendAPIError.invalidResponse }
    }
}
