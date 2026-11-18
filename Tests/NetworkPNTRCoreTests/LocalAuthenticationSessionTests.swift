import Foundation
import XCTest
@testable import NetworkPNTRCore

final class LocalAuthenticationSessionTests: XCTestCase {
    @MainActor private final class Vault: SessionVault {
        var calls = 0
        func load() throws -> String? { calls += 1; throw BackendAPIError.secureStorage(-1) }
        func save(_ token: String) throws { calls += 1; throw BackendAPIError.secureStorage(-1) }
        func remove() throws { calls += 1; throw BackendAPIError.secureStorage(-1) }
    }
    @MainActor private final class API: BackendJSONTransport {
        struct Call { let method: String; let path: String; let body: Data?; let bearer: String? }
        var calls: [Call] = []
        var sessionStatus = 200
        var operationStatus = 200
        var sessionToken = "synthetic.native.jwt"
        var duringSession: (() -> Void)?
        func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
            calls.append(.init(method: method, path: path, body: body, bearer: bearer))
            if path == "/api/auth/local-session" {
                XCTAssertNil(bearer)
                duringSession?()
                return try ChatTestTransport.response(["token":sessionToken], status:sessionStatus)
            }
            XCTAssertEqual(bearer, sessionToken)
            if path == "/api/agents" { return try ChatTestTransport.response(["agents": []]) }
            return try ChatTestTransport.response(["profiles":[]],status:path == "/api/llm/profiles" ? 200 : operationStatus)
        }
    }
    @MainActor func testAutomaticSessionUsesNoPasswordAccountOrKeychain() async throws {
        let api = API(), vault = Vault(), capability = String(repeating:"a",count:64)
        let session = AuthenticationSession(client:api,vault:vault,setupToken:"unused",localCapability:capability)
        await session.refresh()
        XCTAssertEqual(session.phase,.authenticated)
        XCTAssertNotNil(session.exportSessionGeneration)
        XCTAssertEqual(vault.calls,0)
        XCTAssertEqual(api.calls.map(\.path),["/api/auth/local-session","/api/llm/profiles"])
        let body = try XCTUnwrap(api.calls.first?.body)
        XCTAssertEqual(try JSONDecoder().decode([String:String].self,from:body),["capability":capability])
        XCTAssertFalse(String(decoding:body,as:UTF8.self).contains("password"))
        XCTAssertFalse(String(decoding:body,as:UTF8.self).contains("username"))
    }
    @MainActor func testMissingOrInvalidGuestAuthorizationNeverFallsBackToHumanLogin() async {
        for status in [401,403,404,503] {
            let api=API(),vault=Vault();api.sessionStatus=status
            let session=AuthenticationSession(client:api,vault:vault,setupToken:"unused",localCapability:String(repeating:"b",count:64))
            await session.refresh()
            XCTAssertEqual(session.phase,.unavailable)
            XCTAssertNil(session.exportSessionGeneration)
            XCTAssertEqual(api.calls.map(\.path),["/api/auth/local-session"])
            XCTAssertEqual(vault.calls,0)
        }
        let api=API(),vault=Vault()
        let invalid=AuthenticationSession(client:api,vault:vault,setupToken:"unused",localCapability:"invalid")
        await invalid.refresh()
        XCTAssertEqual(invalid.phase,.unavailable);XCTAssertTrue(api.calls.isEmpty);XCTAssertEqual(vault.calls,0)
    }
    @MainActor func testUnauthorizedMutationRevokesBeforeBoundedExplicitReconnectWithoutReplay() async throws {
        let api=API(),vault=Vault();var invalidations=0
        let session=AuthenticationSession(client:api,vault:vault,setupToken:"unused",localCapability:String(repeating:"c",count:64),onInvalidation:{invalidations += 1})
        await session.refresh();let old=session.exportSessionGeneration;let before=invalidations
        api.operationStatus=401
        _ = try await session.authenticatedRequest(method:"POST",path:"/api/tasks",body:Data("{}".utf8))
        XCTAssertEqual(session.phase,.unavailable);XCTAssertNil(session.exportSessionGeneration);XCTAssertGreaterThan(invalidations,before)
        XCTAssertEqual(api.calls.filter{$0.path=="/api/auth/local-session"}.count,1)
        await session.refresh()
        XCTAssertEqual(session.phase,.authenticated);XCTAssertNotEqual(session.exportSessionGeneration,old)
        XCTAssertEqual(api.calls.filter{$0.path=="/api/tasks"}.count,1)
        XCTAssertEqual(api.calls.filter{$0.path=="/api/auth/local-session"}.count,2)
        XCTAssertEqual(vault.calls,0)
    }
    @MainActor func testCanceledBootstrapDoesNotPublishAuthenticatedEpoch() async {
        let api=API(),vault=Vault()
        api.duringSession={withUnsafeCurrentTask{$0?.cancel()}}
        let session=AuthenticationSession(client:api,vault:vault,setupToken:"unused",localCapability:String(repeating:"d",count:64))
        await Task { await session.refresh() }.value
        XCTAssertNotEqual(session.phase,.authenticated)
        XCTAssertNil(session.exportSessionGeneration)
        XCTAssertEqual(api.calls.count,1);XCTAssertEqual(vault.calls,0)
    }
    @MainActor func testCancellationDuringInvalidationDoesNotPublishAuthenticatedEpoch() async {
        let api = API(), vault = Vault()
        var invalidations = 0
        let session = AuthenticationSession(client: api, vault: vault, setupToken: "unused",
            localCapability: String(repeating: "e", count: 64), onInvalidation: {
                invalidations += 1
                if invalidations == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        await Task { await session.refresh() }.value
        XCTAssertNotEqual(session.phase, .authenticated)
        XCTAssertNil(session.exportSessionGeneration)
        XCTAssertEqual(vault.calls, 0)
    }

    @MainActor func testLocal401ImmediatelyRevokesExistingMCPClientAndReconnectCannotRestoreGrant() async throws {
        let api = API(), vault = Vault(), store = MCPClientStore(), runtimeEpoch = UUID()
        let session = AuthenticationSession(client: api, vault: vault, setupToken: "unused",
            localCapability: String(repeating: "f", count: 64), onInvalidation: { store.invalidateAll() })
        await session.refresh()
        await store.revokeAll()
        do {
            let grant = try store.authorize(name: "Automatic-session fixture", agents: true, taskIDs: [],
                language: .english, session: session, runtimeEpoch: { runtimeEpoch })
            let client = try MCPIPCClient(connection: .load(from: grant.connectionFile))
            _ = try await client.call(.agents)
            api.operationStatus = 401
            _ = try await session.authenticatedRequest(method: "POST", path: "/api/tasks", body: Data("{}".utf8))
            let dispatched = api.calls.count
            do { _ = try await client.call(.agents); XCTFail("Old MCP grant survived local 401") } catch {}
            XCTAssertEqual(api.calls.count, dispatched)
            await store.revokeAll()
            XCTAssertFalse(FileManager.default.fileExists(atPath: grant.connectionFile.path))
            await session.refresh()
            await store.revokeAll()
            XCTAssertEqual(session.phase, .authenticated)
            XCTAssertTrue(store.connections.isEmpty)
            do { _ = try await client.call(.agents); XCTFail("Reconnect restored revoked grant") } catch {}
            XCTAssertEqual(api.calls.filter { $0.path == "/api/tasks" }.count, 1)
            XCTAssertEqual(vault.calls, 0)
        } catch {
            await store.revokeAll()
            throw error
        }
        await store.revokeAll()
    }

}
