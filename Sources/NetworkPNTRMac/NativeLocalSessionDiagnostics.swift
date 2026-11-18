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
            Darwin.exit(2)
        }
        var result: [String: Any] = ["complete": false, "visualAcceptance": "pending", "humanCredentialsEntered": false]
        var phase = "artifact_binding"
        var secrets: [String] = ["fixture-non-live-credential-0000"]
        var legacyRuntime: DesktopRuntime?
        do {
            let artifacts = Bundle.main.resourceURL!.appendingPathComponent("Guest")
            let manifestData = try Data(contentsOf: artifacts.appendingPathComponent("manifest.json"))
            let manifestDigest = ArtifactIntegrity.sha256(manifestData)
            guard ["ff958504082071c3f7affc56c4f246049b28bbb8d27ae6593e9da2ebea256868",
                   "40718971e50bd73f9ff5b1cf5bdbc03f55db400f1855fb33d3ef9b3a7c4f4057",
                   "dc0eb715b6bf14205fb7a1dc12d46fdacfe6876655b3701aef755cebf97a14ff"].contains(manifestDigest) else {
                throw RuntimeError.integrity("reviewed local-session manifest")
            }
            let manifest = try GuestArtifacts.load(from: artifacts)
            guard manifest.declaresNativeLocalSession else { throw RuntimeError.integrity("local-session capability declaration") }
            result["manifestSHA256"] = manifestDigest
            result["pinnedSourceCommit"] = "e75ae371ad777ffd1eecdd28d2781a6519b05591"
            result["virtualCPUCount"] = manifest.cpuCount ?? 2
            phase = "startup"
            let legacy = CommandLine.arguments.contains("--local-session-legacy-fixture")
            let initial: DesktopRuntime
            if legacy {
                initial = DesktopRuntime(artifacts: Bundle.main.resourceURL!.appendingPathComponent("Guest"),
                    paths: environment.paths, vault: EphemeralSessionVault())
                legacyRuntime = initial
            } else { initial = environment }
            await initial.start()
            if let provisioning = initial.diagnosticProvisioningForLogAudit {
                secrets += [provisioning.transportToken, provisioning.setupToken]
                if let local = provisioning.localSessionCapability { secrets.append(local) }
            }
            guard let first = initial.authentication else { throw RuntimeError.integrity("fixture startup") }
            if legacy {
                guard first.phase == .needsSetup else { throw RuntimeError.integrity("legacy fixture setup state") }
                let generated = UUID().uuidString + UUID().uuidString
                secrets.append(generated)
                await first.setup(password: generated, confirmation: generated)
            }
            guard first.phase == .authenticated else { throw RuntimeError.integrity("fixture internal connection") }
            guard let firstProvisioning = initial.diagnosticProvisioningForLogAudit,
                  let firstBearer = first.diagnosticBearerForLogAudit else { throw RuntimeError.integrity("first audit secrets") }
            secrets.append(firstBearer)
            phase = "seed_and_probe"
            try await NativeMCPTaskDiagnostics.seed(session: first, directory: directory)
            let llm = try await NativeLLMDiagnostics.run(session: first, directory: directory)
            let fingerprint = try await probe(session: first)
            result["guestToolDoesNotInheritCapability"] = !legacy
            result["firstSessionAuthenticated"] = true
            phase = "restart"
            try await initial.stop()
            await environment.start()
            if let provisioning = environment.diagnosticProvisioningForLogAudit {
                secrets += [provisioning.transportToken, provisioning.setupToken]
                if let local = provisioning.localSessionCapability { secrets.append(local) }
            }
            guard let restored = environment.authentication, restored.phase == .authenticated else {
                throw RuntimeError.integrity("fixture restart connection")
            }
            guard let currentProvisioning = environment.diagnosticProvisioningForLogAudit,
                  let currentCapability = currentProvisioning.localSessionCapability,
                  let currentBearer = restored.diagnosticBearerForLogAudit else { throw RuntimeError.integrity("restart audit secrets") }
            secrets.append(currentBearer)
            let unauthenticated = BackendJSONClient(runtime: environment.controller, provisioning: currentProvisioning)
            let denied = try await unauthenticated.send(method: "GET", path: "/api/llm/profiles", body: nil, bearer: nil)
            guard denied.status == 401 else { throw RuntimeError.integrity("protected API authentication") }
            result["protectedWithoutJWTStatus"] = denied.status
            if let old = firstProvisioning.localSessionCapability {
                guard old != currentCapability else { throw RuntimeError.integrity("per-boot capability rotation") }
                let body = try JSONSerialization.data(withJSONObject: ["capability": old])
                let rejected = try await restored.authenticatedRequest(method: "POST", path: "/api/auth/local-session", body: body)
                guard rejected.status == 403 else { throw RuntimeError.integrity("previous capability rejection") }
                result["oldBootCapabilityRejected"] = true
            }
            try await NativeLLMDiagnostics.verify(llm, session: restored)
            guard try await probe(session: restored) == fingerprint else { throw RuntimeError.integrity("fixture data preservation") }
            result["guestToolDoesNotInheritCapability"] = true
            result["restartAuthenticatedWithoutCredentials"] = true
            result["legacyMigration"] = legacy
            let tasks = try await TaskService(client: AuthenticatedBackendClient(session: restored)).list().tasks
            guard Set(tasks.map(\.id)) == ["7201", "7202"],
                  let selected = tasks.first(where: { $0.id == "7201" }),
                  selected.status == "done", selected.tokens.inputTokens == 4_294_967_294, selected.tokens.outputTokens == 13 else {
                throw RuntimeError.integrity("persisted terminal task metadata")
            }
            result["storedHashProfileKeysTaskRowsAndActivityPreserved"] = true
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
            phase = "stopped_log_audit"
            let logs = try FileManager.default.contentsOfDirectory(at: environment.paths.logs, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("guest-") && $0.pathExtension == "log" }
            guard logs.count == 2 else { throw RuntimeError.integrity("exact native boot attempt count") }
            let audits = logs.map { GuestBootDiagnostics.audit(logFile: $0, tokens: secrets) }
            guard audits.allSatisfy({ $0.complete && $0.credentialsAbsent && $0.isolationWitnessesPresent && $0.diagnostics.isEmpty }) else {
                throw RuntimeError.integrity("complete native secret and isolation log audit")
            }
            result["bootAttempts"] = logs.count
            result["stoppedLogSecretAndIsolationAudit"] = true
            result["complete"] = true
            result["stopped"] = environment.controller.state == .stopped
        } catch {
            // Error bodies, credentials and JWTs are never copied to diagnostic receipts.
            result["failedPhase"] = phase
            result["runtimeState"] = String(describing: environment.controller.state)
            if let legacyRuntime, legacyRuntime.controller.hasMachine { try? await legacyRuntime.forceStop() }
            if environment.controller.hasMachine { try? await environment.forceStop() }
            if !environment.controller.hasMachine && legacyRuntime?.controller.hasMachine != true {
                let logs = (try? FileManager.default.contentsOfDirectory(at: environment.paths.logs, includingPropertiesForKeys: nil)) ?? []
                let audits = logs.filter { $0.lastPathComponent.hasPrefix("guest-") && $0.pathExtension == "log" }
                    .map { GuestBootDiagnostics.audit(logFile: $0, tokens: Array(Set(secrets))) }
                result["bootAttempts"] = audits.count
                result["stoppedLogAudits"] = audits.map { ["complete": $0.complete, "credentialsAbsent": $0.credentialsAbsent,
                    "isolationWitnesses": $0.isolationWitnessesPresent, "diagnostics": $0.diagnostics.map(\.rawValue)] as [String: Any] }
            }
        }
        do {
            try NativeLocalSessionReport.publish(result, at: directory.appendingPathComponent("local-session-results.json"))
        } catch {
            FileHandle.standardError.write(Data("Local-session diagnostic receipt could not be saved\n".utf8))
            Darwin.exit(2)
        }
        guard result["complete"] as? Bool == true, !environment.controller.hasMachine else { Darwin.exit(1) }
        NSApp.terminate(nil)
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
