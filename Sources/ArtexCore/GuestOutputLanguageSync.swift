import Foundation
import OSLog

@MainActor package final class GuestOutputLanguageSync {
    private struct Request {
        let id = UUID()
        let language: AppLanguage
        let session: AuthenticationSession
        let epoch: UUID

        @MainActor var isCurrent: Bool { session.exportSessionGeneration == epoch }
    }

    private struct Settings: Decodable { let outputLanguage: String }
    private struct Change: Encodable { let outputLanguage: AppLanguage }
    private static let logger = Logger(subsystem: "com.nanonigit.artex-mac", category: "guest-language")
    private var pending: Request?
    private var latestID: UUID?
    private var worker: Task<Void, Never>?

    package init() {}

    @discardableResult
    package func update(_ language: AppLanguage, session: AuthenticationSession?) -> Task<Void, Never>? {
        if let session, let epoch = session.exportSessionGeneration {
            pending = Request(language: language, session: session, epoch: epoch)
        } else {
            pending = nil
        }
        latestID = pending?.id
        if worker == nil, pending != nil {
            worker = Task { await drain() }
        }
        return worker
    }

    private func drain() async {
        defer { worker = nil }
        while let request = pending {
            pending = nil
            guard request.isCurrent, latestID == request.id else { continue }
            do {
                let current = try await settings(request.session, method: "GET")
                guard request.isCurrent, latestID == request.id,
                      current.outputLanguage != request.language.rawValue else { continue }
                let change = try BackendJSONCoding.encode(Change(outputLanguage: request.language))
                let saved = try await settings(request.session, method: "PUT", body: change)
                guard saved.outputLanguage == request.language.rawValue else { throw BackendAPIError.invalidResponse }
            } catch {
                if request.isCurrent, latestID == request.id {
                    Self.logger.error("Guest output language synchronization failed")
                }
            }
        }
    }

    private func settings(_ session: AuthenticationSession, method: String, body: Data? = nil) async throws -> Settings {
        let response = try await session.authenticatedRequest(method: method, path: "/api/settings", body: body)
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        return try BackendJSONCoding.decode(Settings.self, from: response.body)
    }
}
