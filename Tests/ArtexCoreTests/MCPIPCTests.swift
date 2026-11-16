import Darwin
import Foundation
import XCTest
@testable import ArtexCore

final class MCPIPCTests: XCTestCase {
    private func directory() -> URL {
        URL(fileURLWithPath: "/private/tmp/artex-mcp-test-" + UUID().uuidString, isDirectory: true)
    }

    @MainActor func testPrivateSocketCarriesTypedReadAndStopInvalidatesConnection() async throws {
        let api = ChatTestTransport(), epoch = UUID()
        try api.enqueue(["agents": [["key": "worker", "name": "worker", "enabled": true, "builtin": true]]])
        let broker = MCPReadBroker(client: api, ownership: { epoch })
        let grant = try broker.authorize(scopes: [.agents])
        let server = try MCPIPCServer(directory: directory(), broker: broker, grant: grant, language: .english)
        let file = server.connectionFile
        let client = try MCPIPCClient(connection: .load(from: file))
        do {
            let data = try await client.call(.agents)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            XCTAssertEqual(object.first?["key"] as? String, "worker")
            XCTAssertEqual(api.calls.map(\.path), ["/api/agents"])
            XCTAssertEqual(api.calls.map(\.method), ["GET"])
            await server.stop()
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            do { _ = try await client.call(.agents); XCTFail("Stopped server") } catch {}
        } catch { await server.stop(); throw error }
    }

    @MainActor func testWrongCapabilityScopeAndTaskDoNotDispatch() async throws {
        let api = ChatTestTransport(), epoch = UUID()
        let broker = MCPReadBroker(client: api, ownership: { epoch })
        let grant = try broker.authorize(scopes: [.taskStatus], taskIDs: ["7"])
        let server = try MCPIPCServer(directory: directory(), broker: broker, grant: grant, language: .english)
        let configuration = try MCPIPCConnection.load(from: server.connectionFile)
        let bad = MCPIPCConnection(version: 1, socketPath: configuration.socketPath, capability: String(repeating: "0", count: 64))
        for client in [MCPIPCClient(connection: bad), MCPIPCClient(connection: configuration)] {
            do { _ = try await client.call(.agents); XCTFail("Unexpected access") } catch {}
        }
        do { _ = try await MCPIPCClient(connection: configuration).call(.taskStatus, taskID: "8"); XCTFail("Foreign task") } catch {}
        XCTAssertTrue(api.calls.isEmpty)
        await server.stop()
    }

    @MainActor func testConnectionFileRejectsSymlinkAndBroadPermissions() async throws {
        let api = ChatTestTransport(), epoch = UUID()
        let broker = MCPReadBroker(client: api, ownership: { epoch })
        let grant = try broker.authorize(scopes: [.agents])
        let server = try MCPIPCServer(directory: directory(), broker: broker, grant: grant, language: .english)
        do {
            let file = server.connectionFile
            XCTAssertEqual(chmod(file.path, 0o644), 0)
            XCTAssertThrowsError(try MCPIPCConnection.load(from: file))
            XCTAssertEqual(chmod(file.path, 0o600), 0)
            let alias = file.deletingLastPathComponent().appendingPathComponent("alias.json")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
            XCTAssertThrowsError(try MCPIPCConnection.load(from: alias))
            XCTAssertEqual(chmod(file.deletingLastPathComponent().path, 0o755), 0)
            XCTAssertThrowsError(try MCPIPCConnection.load(from: file))
            XCTAssertEqual(chmod(file.deletingLastPathComponent().path, 0o700), 0)
            await server.stop()
        } catch { await server.stop(); throw error }
    }

    @MainActor func testBrokerRevocationSuppressesSocketResult() async throws {
        let api = ChatTestTransport(), epoch = UUID()
        let broker = MCPReadBroker(client: api, ownership: { epoch })
        let grant = try broker.authorize(scopes: [.agents])
        let server = try MCPIPCServer(directory: directory(), broker: broker, grant: grant, language: .english)
        let client = try MCPIPCClient(connection: .load(from: server.connectionFile))
        api.handler = { _ in broker.revoke(grant); return try ChatTestTransport.response(["agents": []]) }
        do { _ = try await client.call(.agents); XCTFail("Revoked response") } catch {}
        XCTAssertEqual(api.calls.count, 1)
        await server.stop()
    }

    @MainActor func testConcurrentStopsDrainBeforeRemovingDirectoryAndPreserveReplacement() async throws {
        let api = ChatTestTransport(), epoch = UUID(), path = directory()
        let broker = MCPReadBroker(client: api, ownership: { epoch })
        let grant = try broker.authorize(scopes: [.agents])
        let server = try MCPIPCServer(directory: path, broker: broker, grant: grant, language: .english)
        let client = try MCPIPCClient(connection: .load(from: server.connectionFile))
        var release: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { release = $0 } }
        let request = Task { try await client.call(.agents) }
        for _ in 0..<200 where release == nil { try await Task.sleep(for: .milliseconds(5)) }
        guard let release else { await server.stop(); XCTFail("Handler not entered"); return }
        let stop1 = Task { await server.stop() }, stop2 = Task { await server.stop() }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        release.resume(returning: try ChatTestTransport.response(["agents": []]))
        await stop1.value
        let replacementGrant = try broker.authorize(scopes: [.agents])
        let replacement = try MCPIPCServer(directory: path, broker: broker, grant: replacementGrant, language: .english)
        await stop2.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.connectionFile.path))
        _ = try? await request.value
        await replacement.stop()
    }

    @MainActor func testActualStdioHelperCallsPrivateBrokerWithoutModelEndpoints() async throws {
        let api = ChatTestTransport(), epoch = UUID()
        try api.enqueue(["agents": [["key": "worker", "name": "worker", "enabled": true, "builtin": true]]])
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "task-contract", withExtension: "json", subdirectory: "Fixtures"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        try api.enqueue(try XCTUnwrap(object["task"] as? [String: Any]))
        try api.enqueue(try XCTUnwrap(object["task"] as? [String: Any]))
        var canceledReads = 0
        api.handler = { call in
            if call.path == "/api/agents", api.calls.count > 1 {
                do { try await Task.sleep(for: .seconds(10)) }
                catch { canceledReads += 1; throw error }
            }
            guard !api.replies.isEmpty else { throw BackendAPIError.invalidResponse }
            return api.replies.removeFirst()
        }
        let broker = MCPReadBroker(client: api, ownership: { epoch })
        let grant = try broker.authorize(scopes: [.agents, .taskStatus], taskIDs: ["9007199254740993"])
        let server = try MCPIPCServer(directory: directory(), broker: broker, grant: grant, language: .english)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        let helper = ProcessInfo.processInfo.environment["ARTEX_MCP_TEST_BINARY"] ?? root.appendingPathComponent(".build/debug/ArtexMCP").path
        process.arguments = [root.appendingPathComponent("script/test_mcp_stdio.py").path,
                             helper, server.connectionFile.path]
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            let deadline = ContinuousClock.now + .seconds(20)
            while process.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL); XCTFail("stdio client timeout") }
            while process.isRunning { try await Task.sleep(for: .milliseconds(10)) }
            let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
            XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
            let result = output.fileHandleForReading.readDataToEndOfFile()
            XCTAssertTrue(String(decoding: result, as: UTF8.self).contains("PASS stdio"))
            XCTAssertEqual(Array(api.calls.prefix(2)).map(\.path), ["/api/agents", "/api/tasks/9007199254740993"])
            XCTAssertEqual(api.calls.filter { $0.path == "/api/tasks/9007199254740993" }.count, 2)
            XCTAssertGreaterThan(canceledReads, 0)
            XCTAssertTrue(api.calls.allSatisfy { $0.method == "GET" && ["/api/agents", "/api/tasks/9007199254740993"].contains($0.path) })
            await server.stop()
        } catch {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            await server.stop()
            throw error
        }
    }

    @MainActor func testCanceledClientRetiresBackendReadAndAllowsNextRequest() async throws {
        let api = ChatTestTransport(), epoch = UUID()
        let broker = MCPReadBroker(client: api, ownership: { epoch })
        let grant = try broker.authorize(scopes: [.agents])
        let server = try MCPIPCServer(directory: directory(), broker: broker, grant: grant, language: .english)
        let client = try MCPIPCClient(connection: .load(from: server.connectionFile))
        var entered = false, canceled = false
        api.handler = { _ in
            entered = true
            do { try await Task.sleep(for: .seconds(10)) }
            catch { canceled = true; throw error }
            return try ChatTestTransport.response(["agents": []])
        }
        let request = Task { try await client.call(.agents) }
        for _ in 0..<200 where !entered { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(entered)
        request.cancel()
        do { _ = try await request.value; XCTFail("Canceled request succeeded") } catch {}
        for _ in 0..<200 where !canceled { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(canceled)
        api.handler = nil
        try api.enqueue(["agents": []])
        do {
            let response = try await client.call(.agents)
            XCTAssertEqual(String(decoding: response, as: UTF8.self), "[]")
            await server.stop()
        } catch { await server.stop(); throw error }
    }
}
