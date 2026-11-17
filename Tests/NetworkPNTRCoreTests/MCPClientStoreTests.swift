import Foundation
import XCTest
@testable import NetworkPNTRCore

final class MCPClientStoreTests: XCTestCase {
    @MainActor private final class Vault: SessionVault {
        var value: String?
        func load() throws -> String? { value }
        func save(_ token: String) throws { value = token }
        func remove() throws { value = nil }
    }
    @MainActor private final class Owner { var epoch: UUID? = UUID() }
    @MainActor private final class API: BackendJSONTransport {
        var paths: [String] = []
        var read: (() async throws -> BackendHTTPResponse)?
        func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
            paths.append(path)
            switch path {
            case "/api/auth/status": return try ChatTestTransport.response(["initialized": false, "setup_token_required": true])
            case "/api/auth/init": return try ChatTestTransport.response(["token": "synthetic-session"])
            case "/api/agents":
                XCTAssertEqual(bearer, "synthetic-session")
                return try await read?() ?? ChatTestTransport.response(["agents": []])
            default: throw BackendAPIError.invalidResponse
            }
        }
    }
    @MainActor private func authenticated(_ api: API) async -> AuthenticationSession {
        let session = AuthenticationSession(client: api, vault: Vault(), setupToken: "synthetic-setup")
        await session.refresh()
        await session.setup(password: "synthetic-password", confirmation: "synthetic-password")
        XCTAssertEqual(session.phase, .authenticated)
        return session
    }

    @MainActor func testConfigurationContainsPathsWithoutCapabilityAndNoModelSetup() async throws {
        let api = API(), owner = Owner(), store = MCPClientStore()
        let session = await authenticated(api)
        let connection = try store.authorize(name: "  Local AI  ", agents: true, taskIDs: [], language: .english,
                                              session: session, runtimeEpoch: { owner.epoch })
        XCTAssertEqual(connection.name, "Local AI")
        let text = try connection.clientConfiguration(helper: URL(fileURLWithPath: "/Applications/NetworkPNTR Mac.app/Contents/MacOS/NetworkPNTRMCP"))
        let privateFile = try MCPIPCConnection.load(from: connection.connectionFile)
        XCTAssertFalse(text.contains(privateFile.capability))
        XCTAssertTrue(text.contains("--connection-file"))
        let response = try await MCPIPCClient(connection: privateFile).call(.agents)
        XCTAssertEqual(String(decoding: response, as: UTF8.self), "[]")
        XCTAssertEqual(api.paths, ["/api/auth/status", "/api/auth/init", "/api/agents"])
        await store.revokeAll()
        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: connection.connectionFile.path))
    }

    @MainActor func testInvalidNamesPermissionsAndTasksDoNotCreateClients() async throws {
        let api = API(), owner = Owner(), store = MCPClientStore()
        let session = await authenticated(api)
        for name in [" ", String(repeating: "x", count: 81), "first\nsecond"] {
            XCTAssertThrowsError(try store.authorize(name: name, agents: true, taskIDs: [], language: .english, session: session, runtimeEpoch: { owner.epoch }))
        }
        XCTAssertThrowsError(try store.authorize(name: "AI", agents: false, taskIDs: [], language: .english, session: session, runtimeEpoch: { owner.epoch }))
        XCTAssertThrowsError(try store.authorize(name: "AI", agents: false, taskIDs: ["../7"], language: .english, session: session, runtimeEpoch: { owner.epoch }))
        XCTAssertTrue(store.connections.isEmpty)
        await store.revokeAll()
    }

    @MainActor func testLogoutRetiresConnectionWithoutVisibleView() async throws {
        let api = API(), owner = Owner(), store = MCPClientStore()
        let session = await authenticated(api)
        let connection = try store.authorize(name: "AI", agents: true, taskIDs: [], language: .english, session: session, runtimeEpoch: { owner.epoch })
        session.logout()
        for _ in 0..<200 where !store.connections.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: connection.connectionFile.path))
        await store.revokeAll()
    }

    @MainActor func testRuntimeChangeRejectsReadBeforeDispatchAndRetiresFile() async throws {
        let api = API(), owner = Owner(), store = MCPClientStore()
        let session = await authenticated(api)
        let connection = try store.authorize(name: "AI", agents: true, taskIDs: [], language: .english, session: session, runtimeEpoch: { owner.epoch })
        let client = try MCPIPCClient(connection: .load(from: connection.connectionFile))
        owner.epoch = UUID()
        do { _ = try await client.call(.agents); XCTFail("Stale runtime") } catch {}
        XCTAssertEqual(api.paths.count, 2)
        await store.reconcile()
        XCTAssertTrue(store.connections.isEmpty)
        await store.revokeAll()
    }

    @MainActor func testConcurrentRetirementDrainsAndDoesNotDeleteNewClient() async throws {
        let api = API(), owner = Owner(), store = MCPClientStore()
        let session = await authenticated(api)
        let old = try store.authorize(name: "Old AI", agents: true, taskIDs: [], language: .english, session: session, runtimeEpoch: { owner.epoch })
        let client = try MCPIPCClient(connection: .load(from: old.connectionFile))
        var release: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.read = { try await withCheckedThrowingContinuation { release = $0 } }
        let request = Task { try await client.call(.agents) }
        for _ in 0..<200 where release == nil { try await Task.sleep(for: .milliseconds(5)) }
        guard let release else { await store.revokeAll(); XCTFail("Read not entered"); return }
        let first = Task { await store.revokeAll() }, second = Task { await store.revoke(id: old.id) }
        for _ in 0..<200 where !store.isBusy { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(store.isBusy)
        XCTAssertThrowsError(try store.authorize(name: "Blocked", agents: true, taskIDs: [], language: .english, session: session, runtimeEpoch: { owner.epoch }))
        release.resume(returning: try ChatTestTransport.response(["agents": []]))
        await first.value
        let fresh = try store.authorize(name: "New AI", agents: true, taskIDs: [], language: .english, session: session, runtimeEpoch: { owner.epoch })
        await second.value
        _ = try? await request.value
        XCTAssertEqual(store.connections.map(\.id), [fresh.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.connectionFile.path))
        await store.revokeAll()
    }

    @MainActor func testClientCapacityIsBoundedAndReopensAfterRevocation() async throws {
        let api = API(), owner = Owner(), store = MCPClientStore()
        let session = await authenticated(api)
        for index in 0..<16 {
            _ = try store.authorize(name: "AI \(index)", agents: true, taskIDs: [], language: .english, session: session, runtimeEpoch: { owner.epoch })
        }
        XCTAssertThrowsError(try store.authorize(name: "Overflow", agents: true, taskIDs: [], language: .english, session: session, runtimeEpoch: { owner.epoch }))
        await store.revokeAll()
        XCTAssertTrue(store.connections.isEmpty)
        _ = try store.authorize(name: "Available", agents: true, taskIDs: [], language: .english, session: session, runtimeEpoch: { owner.epoch })
        await store.revokeAll()
    }
}
