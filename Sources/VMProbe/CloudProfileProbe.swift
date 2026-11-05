import ArtexCore
import Darwin
import Foundation

@MainActor enum CloudProfileProbe {
    static func run(_ args: [String]) async {
        #if DEBUG
        if args.count == 2 {
            await runDebug(artifacts: URL(fileURLWithPath: args[0]), output: URL(fileURLWithPath: args[1]))
            return
        }
        #endif
        FileHandle.standardError.write(Data("Usage: DEBUG VMProbe --cloud-profiles ARTIFACTS NEW_PRIVATE_OUTPUT\n".utf8))
        exit(2)
    }

    #if DEBUG
    static let backendVersion = "artex-mac-e75ae371-cloud1"
    private static let backendDigest = "94ce92158f608d1b56b2e19a5e8f73e9eb596019f6fc0df96da1bd2891bedb56"
    private static let pinnedSource = "e75ae371ad777ffd1eecdd28d2781a6519b05591"

    struct Row: Encodable, Equatable {
        let provider: String
        let id: Int64
        let name: String
        let model: String
        let format: LLMFormat
        let baseURL: String
        let streaming: Bool
    }
    struct Snapshot: Equatable {
        let rows: [Row]
        let hints: [String: String]
    }
    private struct Boot: Encodable {
        let generation: UUID
        let backendVersion: String
        let protectedStatus: Int
        let freshSetup: Bool
        let formatted: Bool
        let conversationCount: Int
        let llmRecordCount: Int
        let cooperativeStop: Bool
        let credentialsAbsent: Bool
        let isolationVerified: Bool
    }
    private struct Report: Encodable {
        let passed: Bool
        let stage: String
        let manifestSHA256: String?
        let rows: [Row]
        let boots: [Boot]
        let blankKeyUpdatePreserved: Bool
        let persistedAfterRestart: Bool
        let machineStopped: Bool
    }

    private final class Vault: SessionVault {
        var token: String?
        func load() throws -> String? { token }
        func save(_ token: String) throws { self.token = token }
        func remove() throws { token = nil }
    }

    private final class ProfileTransport: BackendJSONTransport {
        let client: AuthenticatedBackendClient
        let fixtureKeys: [String]
        init(client: AuthenticatedBackendClient, fixtureKeys: [String]) {
            self.client = client
            self.fixtureKeys = fixtureKeys
        }
        func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
            let response = try await client.send(method: method, path: path, body: body, bearer: bearer)
            if method == "GET", path == "/api/llm/profiles", response.status == 200 {
                guard !fixtureKeys.contains(where: { response.body.range(of: Data($0.utf8)) != nil }),
                      let document = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
                      let profiles = document["profiles"] as? [[String: Any]],
                      profiles.allSatisfy({ $0["api_key"] == nil }) else {
                    throw RuntimeError.integrity("cloud profile response credentials")
                }
            }
            return response
        }
    }

    static func validateCandidate(_ metadata: [String: Any]) throws {
        let capabilities = Set(metadata["managedCapabilities"] as? [String] ?? [])
        let required = ["traffic-blob-metadata-v1", "regular-source-blob-stream-v1", "cloud-tool-history-v1"]
        let backend = metadata["managedBackend"] as? [String: Any]
        guard metadata["architecture"] as? String == "arm64", metadata["sourceCommit"] as? String == pinnedSource,
              metadata["bootMode"] as? String == "rootDisk", metadata["cpuCount"] as? Int == 1,
              metadata["networkDevices"] as? Int == 0, metadata["hostShares"] as? Int == 0,
              metadata["backendSHA256"] as? String == backendDigest,
              backend?["binarySHA256"] as? String == backendDigest, backend?["buildVersion"] as? String == backendVersion,
              capabilities.isSuperset(of: required) else {
            throw RuntimeError.integrity("cloud profile candidate")
        }
    }

    static func fixtureDraft(_ provider: LLMCloudProvider) -> LLMProfileDraft {
        var draft = LLMProfileDraft(provider: provider)
        draft.name = "Fixture \(provider.rawValue)"
        draft.model = "fixture-no-cloud-request"
        draft.contextWindowK = 64
        draft.poolExclude = true
        draft.streaming = provider != .groq
        return draft
    }

    static func snapshot(_ profiles: [LLMProfile], ids: [LLMCloudProvider: Int64]) throws -> Snapshot {
        let providers = LLMCloudProvider.allCases
        guard profiles.count == providers.count, Set(ids.keys) == Set(providers), Set(ids.values).count == providers.count else {
            throw RuntimeError.integrity("cloud profile inventory")
        }
        var rows: [Row] = []
        var hints: [String: String] = [:]
        for provider in providers {
            guard let id = ids[provider], id > 0, let profile = profiles.first(where: { $0.id == String(id) }),
                  let hint = profile.apiKeyHint, !hint.isEmpty, !profile.isDefault else {
                throw RuntimeError.integrity("cloud profile identity")
            }
            var expected = fixtureDraft(provider)
            expected.id = id
            guard try LLMProfileDraft(profile: profile) == expected, profile.endpointIdentity.rawValue == provider.rawValue else {
                throw RuntimeError.integrity("cloud profile values")
            }
            hints[provider.rawValue] = hint
            rows.append(Row(provider: provider.rawValue, id: id, name: profile.name, model: profile.model,
                            format: profile.format, baseURL: expected.baseUrl, streaming: expected.streaming))
        }
        return Snapshot(rows: rows, hints: hints)
    }

    private static func runDebug(artifacts: URL, output: URL) async {
        let controller = VMController()
        var stage = "prepare"
        var created = false
        var manifestSHA256: String?
        var baseline: Snapshot?
        var boots: [Boot] = []
        var blankKeyUpdatePreserved = false
        var persistedAfterRestart = false
        func writeReport(passed: Bool) throws {
            let report = Report(passed: passed, stage: stage, manifestSHA256: manifestSHA256, rows: baseline?.rows ?? [],
                                boots: boots, blankKeyUpdatePreserved: blankKeyUpdatePreserved,
                                persistedAfterRestart: persistedAfterRestart, machineStopped: !controller.hasMachine)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: output.appendingPathComponent("cloud-profiles.json"), options: .atomic)
        }
        do {
            let manifest = try Data(contentsOf: artifacts.appendingPathComponent("manifest.json"))
            guard manifest.count <= 64 * 1024, let metadata = try JSONSerialization.jsonObject(with: manifest) as? [String: Any] else {
                throw RuntimeError.integrity("cloud profile manifest")
            }
            try validateCandidate(metadata)
            manifestSHA256 = ArtifactIntegrity.sha256(manifest)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            created = true
            let disk = output.appendingPathComponent("state.ext4")
            _ = try PersistentGuestDisk.createIfMissing(at: disk, byteCount: 2 * 1024 * 1024 * 1024)
            let password = UUID().uuidString + "-fixture"
            let fixtureKeys = Dictionary(uniqueKeysWithValues: LLMCloudProvider.allCases.map { ($0, "fixture-" + UUID().uuidString) })
            var ids: [LLMCloudProvider: Int64] = [:]
            for index in 1...2 {
                stage = "boot-\(index)"
                let logs = output.appendingPathComponent(stage)
                try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let provisioning = try GuestProvisioning.generate()
                try await controller.start(artifacts: artifacts, logs: logs, readinessTimeout: .seconds(120), dataDisk: disk, provisioning: provisioning)
                for _ in 0..<1300 {
                    if controller.guestReady || controller.state == .failed || controller.state == .stopped { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard controller.guestReady, let generation = controller.trafficBlobExportGeneration,
                      !boots.contains(where: { $0.generation == generation }) else { throw RuntimeError.integrity("cloud profile boot") }
                stage = "auth-\(index)"
                let raw = BackendJSONClient(runtime: controller, provisioning: provisioning)
                let health = try await raw.send(method: "GET", path: "/api/health", body: nil, bearer: nil)
                guard health.status == 200, let payload = try JSONSerialization.jsonObject(with: health.body) as? [String: Any],
                      payload["ok"] as? Bool == true, payload["version"] as? String == backendVersion else {
                    throw RuntimeError.integrity("cloud profile health version")
                }
                let denied = try await raw.send(method: "GET", path: "/api/llm/profiles", body: nil, bearer: nil)
                guard denied.status == 401 else { throw RuntimeError.integrity("cloud profile authentication gate") }
                let vault = Vault()
                let session = AuthenticationSession(client: raw, vault: vault, setupToken: provisioning.setupToken)
                await session.refresh()
                if index == 1 {
                    guard session.phase == .needsSetup else { throw RuntimeError.integrity("cloud profile fresh setup") }
                    await session.setup(password: password, confirmation: password)
                } else {
                    guard session.phase == .needsLogin else { throw RuntimeError.integrity("cloud profile restored account") }
                    await session.login(password: password, agreed: true)
                }
                guard session.phase == .authenticated, let token = vault.token else { throw RuntimeError.integrity("cloud profile session") }
                let client = AuthenticatedBackendClient(session: session)
                let service = LLMService(client: ProfileTransport(client: client, fixtureKeys: Array(fixtureKeys.values)))
                stage = "profiles-\(index)"
                if index == 1 {
                    guard try await service.profiles().isEmpty else { throw RuntimeError.integrity("cloud profile fresh database") }
                    for provider in LLMCloudProvider.allCases {
                        var draft = fixtureDraft(provider)
                        guard let key = fixtureKeys[provider] else { throw RuntimeError.integrity("cloud profile fixture key") }
                        draft.apiKey = key
                        ids[provider] = try await service.save(draft)
                    }
                    let profiles = try await service.profiles()
                    let initial = try snapshot(profiles, ids: ids)
                    guard let gemini = profiles.first(where: { $0.endpointIdentity == .gemini }) else {
                        throw RuntimeError.integrity("cloud profile Gemini fixture")
                    }
                    let edit = try LLMProfileDraft(profile: gemini)
                    guard edit.apiKey.isEmpty, try await service.save(edit) == ids[.gemini],
                          try await snapshot(service.profiles(), ids: ids) == initial else {
                        throw RuntimeError.integrity("cloud profile blank key update")
                    }
                    blankKeyUpdatePreserved = true
                    baseline = initial
                } else {
                    guard try await snapshot(service.profiles(), ids: ids) == baseline else {
                        throw RuntimeError.integrity("cloud profile restart persistence")
                    }
                    persistedAfterRestart = true
                }
                stage = "audit-\(index)"
                let conversations = try await ChatService(client: client).conversations()
                let records = try await client.send(method: "GET", path: "/api/llm/records", body: nil, bearer: nil)
                guard conversations.isEmpty, records.status == 200,
                      let document = try JSONSerialization.jsonObject(with: records.body) as? [String: Any],
                      document["total"] as? Int == 0 else { throw RuntimeError.integrity("cloud profile activity audit") }
                session.logout()
                guard session.phase == .needsLogin, vault.token == nil else { throw RuntimeError.integrity("cloud profile logout") }
                try await controller.stop()
                let tokens = [provisioning.transportToken, provisioning.setupToken, password, token] + Array(fixtureKeys.values)
                let audit = GuestBootDiagnostics.audit(logDirectory: logs, tokens: tokens)
                guard !controller.hasMachine, audit.complete, audit.credentialsAbsent, audit.isolationWitnessesPresent,
                      audit.diagnostics.isEmpty, audit.formatStageObserved == (index == 1) else {
                    throw RuntimeError.integrity("cloud profile stopped audit")
                }
                boots.append(Boot(generation: generation, backendVersion: backendVersion, protectedStatus: denied.status,
                                  freshSetup: index == 1, formatted: audit.formatStageObserved, conversationCount: 0, llmRecordCount: 0,
                                  cooperativeStop: true, credentialsAbsent: audit.credentialsAbsent, isolationVerified: audit.isolationWitnessesPresent))
                print("PASS cloud_profile_boot=\(index) version_verified=true profile_count=4 cooperative_stop=true")
            }
            stage = "complete"
            try writeReport(passed: true)
        } catch {
            if controller.hasMachine { try? await controller.forceStop() }
            if created { try? writeReport(passed: false) }
            FileHandle.standardError.write(Data("FAIL cloud_profile_stage=\(stage) machine_stopped=\(!controller.hasMachine)\n".utf8))
            exit(1)
        }
    }
    #endif
}
