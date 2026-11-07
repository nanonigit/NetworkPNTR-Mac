import ArtexCore
import Darwin
import Foundation

@MainActor enum CloudVsockProbe {
    static func run(_ args: [String]) async {
        #if DEBUG
        if args.count == 2 {
            await exercise(artifacts: URL(fileURLWithPath: args[0]), output: URL(fileURLWithPath: args[1]))
            return
        }
        #endif
        FileHandle.standardError.write(Data("Usage: DEBUG VMProbe --cloud-vsock ARTIFACTS NEW_PRIVATE_OUTPUT\n".utf8))
        exit(2)
    }

    #if DEBUG
    private static let manifestDigest = GuestArtifacts.cloudEgressManifestSHA256
    private static let version = "artex-mac-e75ae371-cloud6"
    private static let providers = LLMCloudProvider.allCases

    private final class Vault: SessionVault {
        var token: String?
        func load() throws -> String? { token }
        func save(_ token: String) throws { self.token = token }
        func remove() throws { token = nil }
    }

    private struct Report: Encodable {
        let passed: Bool
        let stage: String
        let manifestSHA256: String
        let machineStopped: Bool
        let fixture: CloudEgressVMFixture.Snapshot
    }

    private static func requireManifest(_ artifacts: URL) throws {
        let url = artifacts.appendingPathComponent("manifest.json")
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw RuntimeError.integrity("cloud vsock manifest file")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: 64 * 1024 + 1) ?? Data()
        guard ArtifactIntegrity.sha256(data) == manifestDigest else {
            throw RuntimeError.integrity("cloud vsock manifest digest")
        }
    }

    private static func waitForReply(_ chat: ChatService, id: Int64, reply: String) async throws {
        for _ in 0..<200 {
            let page = try await chat.history(id: id)
            guard !page.items.contains(where: { $0.isError == true }) else {
                throw RuntimeError.integrity("cloud vsock chat error")
            }
            if !page.running, page.items.contains(where: { $0.kind == "result" && $0.summary == reply }) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw RuntimeError.timeout("cloud vsock reply")
    }

    private static func exercise(artifacts: URL, output: URL) async {
        let controller = VMController()
        let fixture = CloudEgressVMFixture()
        var stage = "prepare"
        var created = false
        func writeReport(_ passed: Bool) throws {
            let report = Report(passed: passed, stage: stage, manifestSHA256: manifestDigest,
                                machineStopped: !controller.hasMachine, fixture: fixture.snapshot)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: output.appendingPathComponent("cloud-vsock.json"), options: .atomic)
        }
        do {
            try requireManifest(artifacts)
            guard mkdir(output.path, 0o700) == 0 else { throw RuntimeError.integrity("new private output required") }
            created = true
            let logs = output.appendingPathComponent("logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let disk = output.appendingPathComponent("state.ext4")
            _ = try PersistentGuestDisk.createIfMissing(at: disk, byteCount: 2 * 1024 * 1024 * 1024)
            stage = "boot"
            let provisioning = try GuestProvisioning.generate()
            try await controller.start(artifacts: artifacts, logs: logs, readinessTimeout: .seconds(120), dataDisk: disk, provisioning: provisioning)
            for _ in 0..<1300 {
                if controller.guestReady || controller.state == .failed || controller.state == .stopped { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard controller.guestReady else { throw RuntimeError.timeout("cloud vsock readiness") }
            stage = "auth"
            let raw = BackendJSONClient(runtime: controller, provisioning: provisioning)
            let health = try await raw.send(method: "GET", path: "/api/health", body: nil, bearer: nil)
            let denied = try await raw.send(method: "GET", path: "/api/conversations", body: nil, bearer: nil)
            guard health.status == 200, denied.status == 401,
                  let payload = try JSONSerialization.jsonObject(with: health.body) as? [String: Any],
                  payload["ok"] as? Bool == true, payload["version"] as? String == version else {
                throw RuntimeError.integrity("cloud vsock backend identity and auth gate")
            }
            let vault = Vault()
            let password = UUID().uuidString + "-vsock-fixture"
            let session = AuthenticationSession(client: raw, vault: vault, setupToken: provisioning.setupToken)
            await session.refresh()
            guard session.phase == .needsSetup else { throw RuntimeError.integrity("cloud vsock fresh account") }
            await session.setup(password: password, confirmation: password)
            guard session.phase == .authenticated, let token = vault.token else {
                throw RuntimeError.integrity("cloud vsock authenticated session")
            }

            stage = "listener"
            try controller.enableCloudEgress(fixture: fixture)
            let client = AuthenticatedBackendClient(session: session)
            let llm = LLMService(client: client)
            let chat = ChatService(client: client)
            var openAIConversation: Int64?
            for provider in providers {
                stage = "models-\(provider.rawValue)"
                var draft = LLMProfileDraft(provider: provider)
                draft.name = "Cloud vsock \(provider.rawValue) fixture"
                draft.model = CloudEgressVMFixture.model(provider)
                draft.apiKey = CloudEgressVMFixture.key
                draft.poolExclude = true
                draft.retry.connect.attempts = -1
                draft.retry.empty.attempts = -1
                draft.retry.stream.attempts = -1
                guard try await llm.models(draft) == [draft.model] else {
                    throw RuntimeError.integrity("cloud vsock model list")
                }
                stage = "chat-\(provider.rawValue)"
                let profile = try await llm.save(draft)
                let id = try await chat.create(agentKey: "mainagent", title: draft.name, profileID: profile).id
                try await chat.send(id: id, message: CloudEgressVMFixture.prompt)
                try await waitForReply(chat, id: id, reply: CloudEgressVMFixture.reply(provider))
                if provider == .openAI { openAIConversation = id }
            }

            stage = "held-stream"
            guard let openAIConversation else { throw RuntimeError.integrity("cloud vsock held chat identity") }
            try await chat.send(id: openAIConversation, message: CloudEgressVMFixture.heldPrompt)
            for _ in 0..<200 {
                if fixture.snapshot.held != 0 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let held = fixture.snapshot
            guard held.held == 1, held.cancelled == 0, held.denied == 0,
                  held.models == providers.map({ "\($0.rawValue).models" }),
                  held.completed == providers.map({ $0 == .anthropic ? "anthropic.messages" : "\($0.rawValue).chat" }) else {
                throw RuntimeError.integrity("cloud vsock route sequence")
            }

            stage = "stop"
            try await controller.stop()
            for _ in 0..<50 {
                if fixture.snapshot.cancelled == 1 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            try requireManifest(artifacts)
            let tokens = [provisioning.transportToken, provisioning.setupToken, password, token, CloudEgressVMFixture.key]
            let audit = GuestBootDiagnostics.audit(logDirectory: logs, tokens: tokens)
            guard !controller.hasMachine, fixture.snapshot.cancelled == 1, fixture.snapshot.denied == 0,
                  audit.complete, audit.credentialsAbsent, audit.isolationWitnessesPresent,
                  audit.diagnostics.isEmpty, audit.formatStageObserved else {
                throw RuntimeError.integrity("cloud vsock stopped audit")
            }
            stage = "complete"
            try writeReport(true)
            print("PASS cloud_vsock models=\(providers.count) chats=\(providers.count) cancelled=1 nic=0 shares=0")
        } catch {
            if controller.hasMachine { try? await controller.forceStop() }
            if created { try? writeReport(false) }
            FileHandle.standardError.write(Data("FAIL cloud_vsock_stage=\(stage) machine_stopped=\(!controller.hasMachine)\n".utf8))
            exit(1)
        }
    }
    #endif
}
