#if DEBUG
import AppKit
import Darwin
import Foundation
import NetworkPNTRCore

/// Explicit disposable native acceptance. Never observes or mutates normal user state.
@MainActor enum NativeLocalSessionDiagnostics {
    static func run(environment: DesktopRuntime, directory: URL) async {
        guard environment.automaticLocalSession,
              NativeMCPTaskDiagnostics.owns(directory: directory, requested: RuntimeFactory.diagnosticsDirectory),
              directory.path.withCString({ Darwin.mkdir($0, 0o700) }) == 0 else {
            FileHandle.standardError.write(Data("Local-session review requires a new private directory\n".utf8))
            NSApp.terminate(nil)
            return
        }
        var result: [String: Any] = ["complete": false, "visualAcceptance": "pending", "humanCredentialsEntered": false]
        var phase = "startup"
        var legacyRuntime: DesktopRuntime?
        do {
            let legacy = CommandLine.arguments.contains("--local-session-legacy-fixture")
            let initial: DesktopRuntime
            if legacy {
                initial = DesktopRuntime(artifacts: Bundle.main.resourceURL!.appendingPathComponent("Guest"),
                    paths: environment.paths, vault: EphemeralSessionVault())
                legacyRuntime = initial
            } else { initial = environment }
            await initial.start()
            guard let first = initial.authentication else { throw RuntimeError.integrity("fixture startup") }
            if legacy {
                guard first.phase == .needsSetup else { throw RuntimeError.integrity("legacy fixture setup state") }
                let generated = UUID().uuidString + UUID().uuidString
                await first.setup(password: generated, confirmation: generated)
            }
            guard first.phase == .authenticated else { throw RuntimeError.integrity("fixture internal connection") }
            phase = "seed_and_probe"
            let llm = try await NativeLLMDiagnostics.run(session: first, directory: directory)
            let fingerprint = try await probe(session: first)
            result["guestToolDoesNotInheritCapability"] = !legacy
            result["firstSessionAuthenticated"] = true
            phase = "restart"
            try await initial.stop()
            await environment.start()
            guard let restored = environment.authentication, restored.phase == .authenticated else {
                throw RuntimeError.integrity("fixture restart connection")
            }
            try await NativeLLMDiagnostics.verify(llm, session: restored)
            guard try await probe(session: restored) == fingerprint else { throw RuntimeError.integrity("fixture data preservation") }
            result["guestToolDoesNotInheritCapability"] = true
            result["restartAuthenticatedWithoutCredentials"] = true
            result["legacyMigration"] = legacy
            result["storedHashProfilesKeysTasksPreserved"] = true
            result["mcpGrantsAfterRestart"] = environment.mcp.connections.count
            guard environment.mcp.connections.isEmpty else { throw RuntimeError.integrity("unexpected fixture MCP grant") }
            phase = "native_review"
            try Data().write(to: directory.appendingPathComponent("native-review-ready"))
            if CommandLine.arguments.contains("--native-review") {
                for _ in 0..<6000 {
                    if FileManager.default.fileExists(atPath: directory.appendingPathComponent("native-review-finish").path) { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("native-review-finish").path) else {
                    throw RuntimeError.timeout("local-session visual review")
                }
            }
            phase = "stop"
            try await environment.stop()
            result["complete"] = true
            result["stopped"] = environment.controller.state == .stopped
        } catch {
            // Error bodies, credentials and JWTs are never copied to diagnostic receipts.
            result["failedPhase"] = phase
            result["runtimeState"] = String(describing: environment.controller.state)
            if let legacyRuntime, legacyRuntime.controller.hasMachine { try? await legacyRuntime.forceStop() }
            if environment.controller.hasMachine { try? await environment.forceStop() }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("local-session-results.json"), options: .atomic)
        }
        if !environment.controller.hasMachine { NSApp.terminate(nil) }
    }

    private static func probe(session: AuthenticationSession) async throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let code = try String(contentsOf: root.appendingPathComponent("script/local_session_probe_guest.py"), encoding: .utf8)
        let body = try JSONSerialization.data(withJSONObject: ["kind": "script", "exec": ["code": code, "timeout_ms": 10_000], "params": [:]])
        let response = try await session.authenticatedRequest(method: "POST", path: "/api/tools/custom/test", body: body)
        guard response.status == 200, let record = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              record["is_error"] as? Bool == false, let output = record["output"] as? String,
              output.utf8.count < 1024, let data = output.data(using: .utf8),
              let proof = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              proof["capabilityNotInherited"] as? Bool == true, proof["usage"] as? Int == 0,
              let digest = proof["fingerprint"] as? String, digest.count == 64 else {
            throw RuntimeError.integrity("guest local-session preservation proof")
        }
        return digest
    }
}
#endif
