import ArtexCore
import Darwin
import Foundation

@MainActor enum OllamaGuestProbe {
    static func run(_ args: [String]) async {
        #if DEBUG
        guard args.count == 3 else { exit(2) }
        let artifacts = URL(fileURLWithPath: args[0])
        let output = URL(fileURLWithPath: args[1])
        let model = args[2]
        let controller = VMController()
        let fixture = OllamaGuestFixture(model: model)
        var stage = "prepare"
        var prepared = false
        var passed = false
        func writeReport(_ accepted: Bool, audit: GuestBootLogAudit? = nil) throws {
            let report: [String: Any] = [
                "passed": accepted, "stage": stage, "model": model,
                "completedLocalExchanges": fixture.requestCount,
                "machineStopped": !controller.hasMachine,
                "manifestSHA256": reviewedManifestDigest,
                "verifiedContextLength": accepted ? OllamaGuestFixture.contextLength : 0,
                "logAuditComplete": audit?.complete ?? false,
                "credentialLogCheckPassed": audit?.credentialsAbsent ?? false,
                "isolationVerified": audit?.isolationWitnessesPresent ?? false,
                "scope": "Disposable guest existing agent through diagnostic local inference broker"
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: output.appendingPathComponent("local-inference.json"), options: .atomic)
        }
        defer {
            if !passed {
                if prepared { try? writeReport(false) }
                exit(1)
            }
        }
        do {
            try requireReviewedManifest(artifacts)
            let runtime = OllamaCatalog()
            try await runtime.requireLocalOnly()
            guard try await runtime.installed().models.contains(where: { $0.name == model }) else {
                throw RuntimeError.integrity("selected local model must be installed")
            }
            guard mkdir(output.path, 0o700) == 0 else { throw RuntimeError.integrity("new private output required") }
            prepared = true
            let logs = output.appendingPathComponent("logs")
            let disk = output.appendingPathComponent("state.ext4")
            _ = try PersistentGuestDisk.createIfMissing(at: disk, byteCount: 2 * 1_024 * 1_024 * 1_024)
            let provisioning = try GuestProvisioning.generate()
            stage = "boot"
            try await controller.start(artifacts: artifacts, logs: logs, readinessTimeout: .seconds(120), dataDisk: disk, provisioning: provisioning)
            for _ in 0..<1_300 {
                if controller.guestReady || controller.state == .failed { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard controller.guestReady else { throw RuntimeError.timeout("local inference guest readiness") }
            stage = "authentication"
            let vault = MemoryVault()
            let session = AuthenticationSession(
                client: BackendJSONClient(runtime: controller, provisioning: provisioning),
                vault: vault, setupToken: provisioning.setupToken
            )
            await session.refresh()
            let password = UUID().uuidString + "-local-fixture"
            await session.setup(password: password, confirmation: password)
            guard session.phase == .authenticated else { throw RuntimeError.integrity("local inference fixture authentication") }
            try controller.enableLocalInferenceFixture(fixture)
            let client = AuthenticatedBackendClient(session: session)
            let profiles = LLMService(client: client)
            var draft = LLMProfileDraft(provider: .openAI)
            draft.name = "Local inference diagnostic"
            draft.model = model
            draft.apiKey = OllamaGuestFixture.key
            draft.streaming = true
            draft.maxTokens = 2_048
            draft.maxTokensField = "max_tokens"
            draft.poolExclude = true
            draft.retry.connect.attempts = -1
            draft.retry.empty.attempts = -1
            draft.retry.stream.attempts = -1
            let profileID = try await profiles.save(draft)
            let chat = ChatService(client: client)
            let conversation = try await chat.create(agentKey: "mainagent", title: "Local model proof", profileID: profileID)
            stage = "agent-inference"
            try await chat.send(id: conversation.id, message: "Reply with LOCAL_PROOF_OK. Do not call any tools.")
            var received = false
            for _ in 0..<1_200 {
                let page = try await chat.history(id: conversation.id)
                guard !page.items.contains(where: { $0.isError == true }) else {
                    throw RuntimeError.integrity("local inference agent error")
                }
                if !page.running, page.items.contains(where: { $0.kind == "result" && $0.summary.contains("LOCAL_PROOF_OK") }) {
                    received = true
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard received, fixture.requestCount > 0 else { throw RuntimeError.timeout("local agent response") }
            stage = "stop"
            try await controller.stop()
            guard !controller.hasMachine else { throw RuntimeError.integrity("local inference VM shutdown") }
            try requireReviewedManifest(artifacts)
            let tokens = [provisioning.transportToken, provisioning.setupToken, password, OllamaGuestFixture.key] + [try vault.load()].compactMap { $0 }
            let audit = GuestBootDiagnostics.audit(logDirectory: logs, tokens: tokens)
            guard audit.complete, audit.credentialsAbsent, audit.isolationWitnessesPresent,
                  audit.diagnostics.isEmpty else { throw RuntimeError.integrity("stopped local inference audit") }
            stage = "complete"
            try writeReport(true, audit: audit)
            passed = true
            print("PASS existing_guest_agent_local_model=true streaming=true machine_stopped=true")
        } catch {
            if controller.hasMachine { try? await controller.forceStop() }
            FileHandle.standardError.write(Data("FAIL local_inference_stage=\(stage)\n".utf8))
        }
        #else
        exit(2)
        #endif
    }

    #if DEBUG
    private static let reviewedManifestDigest = "7ab7cb7f5620f8470e73a1e7a9a6ee634e09905382b9564bff997cd3504e52c0"

    private static func requireReviewedManifest(_ artifacts: URL) throws {
        let data = try Data(contentsOf: artifacts.appendingPathComponent("manifest.json"))
        guard ArtifactIntegrity.sha256(data) == reviewedManifestDigest else {
            throw RuntimeError.integrity("reviewed local inference guest manifest")
        }
    }

    private final class MemoryVault: SessionVault {
        private var token: String?
        func load() throws -> String? { token }
        func save(_ token: String) throws { self.token = token }
        func remove() throws { token = nil }
    }
    #endif
}
