import Foundation
import XCTest
@testable import NetworkPNTRCore

final class MCPReadBrokerTests: XCTestCase {
    @MainActor private final class Owner { var epoch: UUID? = UUID() }
    @MainActor private final class Vault: SessionVault {
        var value: String?
        func load() throws -> String? { value }
        func save(_ token: String) throws { value = token }
        func remove() throws { value = nil }
    }
    @MainActor private final class SessionAPI: BackendJSONTransport {
        var paths: [String] = []
        func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
            paths.append(path)
            switch path {
            case "/api/auth/status":
                return try ChatTestTransport.response(["initialized": false, "setup_token_required": true])
            case "/api/auth/init":
                return try ChatTestTransport.response(["token": "synthetic-session-token"])
            case "/api/agents":
                XCTAssertEqual(bearer, "synthetic-session-token")
                return try ChatTestTransport.response(["agents": []])
            default: throw BackendAPIError.invalidResponse
            }
        }
    }

    @MainActor func testProductionFactoryBindsAuthenticatedAccountAndRuntimeWithoutLLMProfile() async throws {
        let api = SessionAPI(), owner = Owner()
        let session = AuthenticationSession(client: api, vault: Vault(), setupToken: "synthetic-setup")
        XCTAssertThrowsError(try MCPReadBroker(session: session, runtimeEpoch: { owner.epoch }))
        await session.refresh()
        await session.setup(password: "synthetic-password", confirmation: "synthetic-password")
        XCTAssertEqual(session.phase, .authenticated)
        let broker = try MCPReadBroker(session: session, runtimeEpoch: { owner.epoch })
        let grant = try broker.authorize(scopes: [.agents])
        let result = try await broker.agents(grant: grant, language: .english)
        XCTAssertTrue(result.isEmpty)
        owner.epoch = UUID()
        XCTAssertThrowsError(try broker.authorize(scopes: [.agents]))
        let current = try MCPReadBroker(session: session, runtimeEpoch: { owner.epoch })
        let currentGrant = try current.authorize(scopes: [.agents])
        session.logout()
        do { _ = try await current.agents(grant: currentGrant, language: .english); XCTFail("Logged-out account") }
        catch { XCTAssertEqual(error as? MCPReadError, .unauthorized) }
        XCTAssertEqual(api.paths, ["/api/auth/status", "/api/auth/init", "/api/agents"])
    }

    @MainActor func testDiscoveryUsesOnlyTypedReadWithoutModelConfiguration() async throws {
        let api = ChatTestTransport(), owner = Owner()
        try api.enqueue(["agents": [["key": "worker", "name": "seed", "builtin": true, "enabled": true,
                                     "description": "private prompt must not be projected"]]])
        let broker = MCPReadBroker(client: api, ownership: { owner.epoch })
        let grant = try broker.authorize(scopes: [.agents])
        let result = try await broker.agents(grant: grant, language: .english)
        XCTAssertEqual(result.map(\.key), ["worker"])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [[String: Any]]
        XCTAssertEqual(Set(try XCTUnwrap(encoded?.first).keys), ["key", "name", "enabled"])
        XCTAssertEqual(api.calls.map(\.method), ["GET"])
        XCTAssertEqual(api.calls.map(\.path), ["/api/agents"])
        XCTAssertNil(api.calls.first?.body)
    }

    @MainActor func testScopedStatusPreservesLargeIDsAndTokenCounts() async throws {
        let api = ChatTestTransport(), owner = Owner()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-contract", withExtension: "json", subdirectory: "Fixtures"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let item = try XCTUnwrap(root["task"] as? [String: Any])
        try api.enqueue(item)
        let broker = MCPReadBroker(client: api, ownership: { owner.epoch })
        let id = "9007199254740993"
        let grant = try broker.authorize(scopes: [.taskStatus], taskIDs: [id])
        let status = try await broker.taskStatus(grant: grant, id: id)
        XCTAssertEqual(status.id, id)
        XCTAssertEqual(status.inputTokens, 9_007_199_254_740_993)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as? [String: Any])
        XCTAssertEqual(Set(encoded.keys), ["id", "status", "paused", "queued", "inputTokens", "outputTokens"])
        XCTAssertEqual(api.calls.map(\.path), ["/api/tasks/" + id])
        XCTAssertEqual(api.calls.map(\.method), ["GET"])
    }

    @MainActor func testScopesForeignTasksAndForeignBrokerDeniedBeforeDispatch() async throws {
        let api = ChatTestTransport(), owner = Owner()
        let broker = MCPReadBroker(client: api, ownership: { owner.epoch })
        let agents = try broker.authorize(scopes: [.agents])
        let status = try broker.authorize(scopes: [.taskStatus], taskIDs: ["7"])
        let foreign = try MCPReadBroker(client: api, ownership: { owner.epoch }).authorize(scopes: [.agents])
        for grant in [status, foreign] {
            do { _ = try await broker.agents(grant: grant, language: .english); XCTFail("Unexpected access") }
            catch { XCTAssertEqual(error as? MCPReadError, .unauthorized) }
        }
        for (grant, id) in [(agents, "7"), (status, "8"), (status, "../7"), (status, "0007")] {
            do { _ = try await broker.taskStatus(grant: grant, id: id); XCTFail("Unexpected task access") }
            catch { XCTAssertEqual(error as? MCPReadError, .unauthorized) }
        }
        XCTAssertTrue(api.calls.isEmpty)
    }

    @MainActor func testRevocationAndOwnershipChangeSuppressInFlightResult() async throws {
        for changeOwner in [false, true] {
            let api = ChatTestTransport(), owner = Owner()
            let broker = MCPReadBroker(client: api, ownership: { owner.epoch })
            let grant = try broker.authorize(scopes: [.agents])
            api.handler = { _ in
                if changeOwner { owner.epoch = UUID() } else { broker.revoke(grant) }
                await Task.yield()
                return try ChatTestTransport.response(["agents": []])
            }
            do { _ = try await broker.agents(grant: grant, language: .english); XCTFail("Stale response released") }
            catch { XCTAssertEqual(error as? MCPReadError, .unauthorized) }
            XCTAssertEqual(api.calls.count, 1)
        }
    }

    @MainActor func testLoggedOutRevokedAndCanceledRequestsDoNotDispatch() async throws {
        let api = ChatTestTransport(), owner = Owner()
        let broker = MCPReadBroker(client: api, ownership: { owner.epoch })
        let revoked = try broker.authorize(scopes: [.agents])
        broker.revokeAll()
        do { _ = try await broker.agents(grant: revoked, language: .english); XCTFail("Revoked grant") }
        catch { XCTAssertEqual(error as? MCPReadError, .unauthorized) }
        let grant = try broker.authorize(scopes: [.agents])
        let operation = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await broker.agents(grant: grant, language: .english)
        }
        do { _ = try await operation.value; XCTFail("Canceled request") } catch is CancellationError {}
        owner.epoch = nil
        XCTAssertThrowsError(try broker.authorize(scopes: [.agents]))
        do { _ = try await broker.agents(grant: grant, language: .english); XCTFail("Logged out") }
        catch { XCTAssertEqual(error as? MCPReadError, .unauthorized) }
        XCTAssertTrue(api.calls.isEmpty)
    }

    @MainActor func testInvalidGrantAndGrantCapacityAreBounded() throws {
        let owner = Owner()
        let broker = MCPReadBroker(client: ChatTestTransport(), ownership: { owner.epoch })
        XCTAssertThrowsError(try broker.authorize(scopes: []))
        XCTAssertThrowsError(try broker.authorize(scopes: [.agents], taskIDs: ["7"]))
        XCTAssertThrowsError(try broker.authorize(scopes: [.taskStatus], taskIDs: ["../7"]))
        for _ in 0..<128 { _ = try broker.authorize(scopes: [.agents]) }
        XCTAssertThrowsError(try broker.authorize(scopes: [.agents]))
        broker.revokeAll()
        XCTAssertNoThrow(try broker.authorize(scopes: [.agents]))
    }

    @MainActor func testOwnershipCallbackRevocationCannotReleaseStaleAuthorization() async throws {
        for afterResponse in [false, true] {
            let api = ChatTestTransport(), owner = Owner()
            var callback: (() -> Void)?
            let broker = MCPReadBroker(client: api, ownership: { callback?(); return owner.epoch })
            let grant = try broker.authorize(scopes: [.agents])
            let revoke = { broker.revoke(grant) }
            if afterResponse {
                api.handler = { _ in callback = revoke; return try ChatTestTransport.response(["agents": []]) }
            } else { callback = revoke }
            do { _ = try await broker.agents(grant: grant, language: .english); XCTFail("Reentrant revocation ignored") }
            catch { XCTAssertEqual(error as? MCPReadError, .unauthorized) }
            XCTAssertEqual(api.calls.count, afterResponse ? 1 : 0)
            callback = nil
        }
    }

    @MainActor func testOwnershipCallbackCancellationCannotDispatchOrReleaseResponse() async throws {
        for afterResponse in [false, true] {
            let api = ChatTestTransport(), owner = Owner()
            var cancel = false
            let broker = MCPReadBroker(client: api, ownership: {
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
                return owner.epoch
            })
            let grant = try broker.authorize(scopes: [.agents])
            if afterResponse {
                api.handler = { _ in cancel = true; return try ChatTestTransport.response(["agents": []]) }
            } else { cancel = true }
            let operation = Task { @MainActor in try await broker.agents(grant: grant, language: .english) }
            do { _ = try await operation.value; XCTFail("Reentrant cancellation ignored") } catch is CancellationError {}
            XCTAssertEqual(api.calls.count, afterResponse ? 1 : 0)
        }
    }
}
