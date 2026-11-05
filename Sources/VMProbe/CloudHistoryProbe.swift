import ArtexCore
import Darwin
import Foundation

@MainActor enum CloudHistoryProbe {
    static func run(_ args: [String]) async {
        #if DEBUG
        if args.count == 2 {
            await exercise(artifacts: URL(fileURLWithPath: args[0]), output: URL(fileURLWithPath: args[1]))
            return
        }
        #endif
        FileHandle.standardError.write(Data("Usage: DEBUG VMProbe --cloud-history ARTIFACTS NEW_PRIVATE_OUTPUT\n".utf8))
        exit(2)
    }

    #if DEBUG
    private static let manifestDigest = "6e0b5a801093841923afdd42fb234383297037b6eb9af1426de1e0aad274f08e"
    private static let version = "artex-mac-e75ae371-cloud2"
    private static let baseURL = "http://127.0.0.1:8791/v1beta/openai/"
    private static let fixtureKey = "synthetic-vm-history-key"
    private static let model = "fixture-vm-history-model"
    private static let initialPrompt = "Read the local VM history fixture"
    private static let resumePrompt = "Continue the saved VM history fixture"
    private static let initialReply = "VM fixture tool result accepted"
    private static let resumeReply = "VM fixture saved history accepted"
    private static let finalActivityKind = "result"
    private static let toolCallID = "call-vm-read-witness"

    struct History: Encodable, Equatable {
        let toolUseSequence: Int64
        let toolResultSequence: Int64
        let firstReplySequence: Int64
        let resumedReplySequence: Int64?
    }

    private struct Boot: Encodable {
        let generation: UUID
        let backendVersion: String
        let protectedStatus: Int
        let formatted: Bool
        let fixtureRequests: Int
        let cooperativeStop: Bool
        let isolationVerified: Bool
        let credentialsAbsent: Bool
        let history: History
    }

    private final class Vault: SessionVault {
        var token: String?
        func load() throws -> String? { token }
        func save(_ token: String) throws { self.token = token }
        func remove() throws { token = nil }
    }

    static func verifyHistory(_ page: ChatPage, resumed: Bool) throws -> History {
        func one(_ kind: String, _ summary: String) -> ChatActivity? {
            let matches = page.items.filter { $0.kind == kind && $0.summary == summary }
            return matches.count == 1 ? matches[0] : nil
        }
        let uses = page.items.filter { $0.kind == "tool_use" }
        let results = page.items.filter { $0.kind == "tool_result" }
        guard !page.running, !page.hasMore, page.items.allSatisfy({ $0.isError != true }),
              uses.count == 1, results.count == 1, let use = uses.first, let result = results.first,
              use.tool == "Read", use.toolUseId == toolCallID, result.toolUseId == toolCallID,
              let initial = one("user", initialPrompt), let first = one(finalActivityKind, initialReply),
              initial.seq < use.seq, use.seq < result.seq, result.seq < first.seq else {
            throw RuntimeError.integrity("cloud history activity")
        }
        var resumedReply: Int64?
        if resumed {
            guard let user = one("user", resumePrompt), let reply = one(finalActivityKind, resumeReply),
                  first.seq < user.seq, user.seq < reply.seq else { throw RuntimeError.integrity("cloud history resume activity") }
            resumedReply = reply.seq
        } else {
            guard !page.items.contains(where: { $0.summary == resumePrompt || $0.summary == resumeReply }) else {
                throw RuntimeError.integrity("unexpected cloud continuation")
            }
        }
        return History(toolUseSequence: use.seq, toolResultSequence: result.seq,
                       firstReplySequence: first.seq, resumedReplySequence: resumedReply)
    }

    private static func requireManifest(_ artifacts: URL) throws {
        let url = artifacts.appendingPathComponent("manifest.json")
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw RuntimeError.integrity("cloud history manifest file") }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: 64 * 1024 + 1) ?? Data()
        guard data.count <= 64 * 1024, ArtifactIntegrity.sha256(data) == manifestDigest else {
            throw RuntimeError.integrity("cloud history manifest digest")
        }
    }

    private static func waitForHistory(_ chat: ChatService, conversation: Int64, resumed: Bool) async throws -> History {
        let expected = resumed ? resumeReply : initialReply
        for _ in 0..<200 {
            let page = try await chat.history(id: conversation)
            guard !page.items.contains(where: { $0.isError == true }) else { throw RuntimeError.integrity("cloud history tool or model error") }
            if !page.running, page.items.contains(where: { $0.kind == finalActivityKind && $0.summary == expected }) {
                return try verifyHistory(page, resumed: resumed)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw RuntimeError.timeout("cloud history turn")
    }

    private static func exercise(artifacts: URL, output: URL) async {
        let controller = VMController()
        var stage = "prepare"
        var created = false
        var profileID: Int64?
        var conversationID: Int64?
        var boots: [Boot] = []
        func writeReport(_ passed: Bool) throws {
            struct Report: Encodable {
                let passed: Bool
                let stage: String
                let manifestSHA256: String
                let profileID: Int64?
                let conversationID: Int64?
                let boots: [Boot]
                let machineStopped: Bool
            }
            let report = Report(passed: passed, stage: stage, manifestSHA256: manifestDigest, profileID: profileID,
                                conversationID: conversationID, boots: boots, machineStopped: !controller.hasMachine)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: output.appendingPathComponent("cloud-history.json"), options: .atomic)
        }
        do {
            try requireManifest(artifacts)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            created = true
            let disk = output.appendingPathComponent("state.ext4")
            _ = try PersistentGuestDisk.createIfMissing(at: disk, byteCount: 2 * 1024 * 1024 * 1024)
            let password = UUID().uuidString + "-history-fixture"
            for index in 1...2 {
                let resumed = index == 2
                stage = "boot-\(index)"
                try requireManifest(artifacts)
                let logs = output.appendingPathComponent(stage)
                try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let provisioning = try GuestProvisioning.generate()
                try await controller.start(artifacts: artifacts, logs: logs, readinessTimeout: .seconds(120), dataDisk: disk, provisioning: provisioning)
                for _ in 0..<1300 {
                    if controller.guestReady || controller.state == .failed || controller.state == .stopped { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard controller.guestReady, let generation = controller.trafficBlobExportGeneration,
                      !boots.contains(where: { $0.generation == generation }) else { throw RuntimeError.integrity("cloud history boot") }
                stage = "auth-\(index)"
                let raw = BackendJSONClient(runtime: controller, provisioning: provisioning)
                let health = try await raw.send(method: "GET", path: "/api/health", body: nil, bearer: nil)
                guard health.status == 200, let payload = try JSONSerialization.jsonObject(with: health.body) as? [String: Any],
                      payload["ok"] as? Bool == true, payload["version"] as? String == version else {
                    throw RuntimeError.integrity("cloud history backend version")
                }
                let denied = try await raw.send(method: "GET", path: "/api/conversations", body: nil, bearer: nil)
                guard denied.status == 401 else { throw RuntimeError.integrity("cloud history auth gate") }
                let vault = Vault()
                let session = AuthenticationSession(client: raw, vault: vault, setupToken: provisioning.setupToken)
                await session.refresh()
                if resumed {
                    guard session.phase == .needsLogin else { throw RuntimeError.integrity("cloud history persisted account") }
                    await session.login(password: password, agreed: true)
                } else {
                    guard session.phase == .needsSetup else { throw RuntimeError.integrity("cloud history fresh account") }
                    await session.setup(password: password, confirmation: password)
                }
                guard session.phase == .authenticated, let token = vault.token else { throw RuntimeError.integrity("cloud history session") }
                let client = AuthenticatedBackendClient(session: session)
                let llm = LLMService(client: client)
                let chat = ChatService(client: client)
                stage = "conversation-\(index)"
                if !resumed {
                    guard try await llm.profiles().isEmpty, try await chat.conversations().isEmpty else {
                        throw RuntimeError.integrity("cloud history fresh state")
                    }
                    var draft = LLMProfileDraft()
                    draft.name = "VM history loopback fixture"
                    draft.format = .openai
                    draft.baseUrl = baseURL
                    draft.model = model
                    draft.apiKey = fixtureKey
                    draft.poolExclude = true
                    draft.retry.connect.attempts = -1
                    draft.retry.empty.attempts = -1
                    draft.retry.stream.attempts = -1
                    let saved = try await llm.save(draft)
                    profileID = saved
                    conversationID = try await chat.create(agentKey: "mainagent", title: "VM history fixture", profileID: saved).id
                }
                guard let profileID, let conversationID else { throw RuntimeError.integrity("cloud history identities") }
                let profiles = try await llm.profiles()
                let conversations = try await chat.conversations()
                guard profiles.count == 1, let profile = profiles.first, profile.id == String(profileID),
                      profile.baseUrl == baseURL, profile.model == model, profile.format == .openai, profile.streaming == true,
                      conversations.count == 1, let conversation = conversations.first,
                      conversation.id == conversationID, conversation.llmProfileId == profileID, conversation.agentKey == "mainagent" else {
                    throw RuntimeError.integrity("cloud history persisted binding")
                }
                if resumed {
                    let saved = try await verifyHistory(chat.history(id: conversationID), resumed: false)
                    guard saved == boots.first?.history else { throw RuntimeError.integrity("cloud history persisted activity") }
                }
                stage = "turn-\(index)"
                try await chat.send(id: conversationID, message: resumed ? resumePrompt : initialPrompt)
                let history = try await waitForHistory(chat, conversation: conversationID, resumed: resumed)
                if resumed {
                    guard let previous = boots.first?.history, history.toolUseSequence == previous.toolUseSequence,
                          history.toolResultSequence == previous.toolResultSequence, history.firstReplySequence == previous.firstReplySequence else {
                        throw RuntimeError.integrity("cloud history replay identity")
                    }
                }
                stage = "stop-\(index)"
                session.logout()
                guard vault.token == nil else { throw RuntimeError.integrity("cloud history logout") }
                try await controller.stop()
                try requireManifest(artifacts)
                let tokens = [provisioning.transportToken, provisioning.setupToken, password, token, fixtureKey]
                let audit = GuestBootDiagnostics.audit(logDirectory: logs, tokens: tokens)
                let files = try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
                guard !controller.hasMachine, audit.complete, audit.credentialsAbsent, audit.isolationWitnessesPresent,
                      audit.diagnostics.isEmpty, audit.formatStageObserved == !resumed,
                      let log = files.first(where: { $0.lastPathComponent.hasPrefix("guest-") && $0.pathExtension == "log" }) else {
                    throw RuntimeError.integrity("cloud history stopped audit")
                }
                let lines = try String(contentsOf: log, encoding: .utf8).components(separatedBy: .newlines)
                let phase = resumed ? "resume" : "first"
                let requests = resumed ? 1 : 2
                guard lines.filter({ $0.hasPrefix("ARTEX_CLOUD_HISTORY_READY ") }) == ["ARTEX_CLOUD_HISTORY_READY phase=\(phase)"],
                      lines.filter({ $0.hasPrefix("ARTEX_CLOUD_HISTORY_ACCEPTED ") }) == ["ARTEX_CLOUD_HISTORY_ACCEPTED phase=\(phase) requests=\(requests)"],
                      !lines.contains(where: { $0.hasPrefix("ARTEX_CLOUD_HISTORY_REJECTED ") }) else {
                    throw RuntimeError.integrity("cloud history provider witness")
                }
                boots.append(Boot(generation: generation, backendVersion: version, protectedStatus: denied.status,
                                  formatted: audit.formatStageObserved, fixtureRequests: requests, cooperativeStop: true,
                                  isolationVerified: audit.isolationWitnessesPresent, credentialsAbsent: audit.credentialsAbsent, history: history))
                print("PASS cloud_history_boot=\(index) requests=\(requests) cooperative_stop=true")
            }
            stage = "complete"
            try writeReport(true)
        } catch {
            if controller.hasMachine { try? await controller.forceStop() }
            if created { try? writeReport(false) }
            FileHandle.standardError.write(Data("FAIL cloud_history_stage=\(stage) machine_stopped=\(!controller.hasMachine)\n".utf8))
            exit(1)
        }
    }
    #endif
}
